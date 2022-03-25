needs "Cloning Libs/Cloning"
needs "Standard Libs/Debug Lib"
needs "Cloning Libs/OpenTronsAq"

# DESIGNED FOR BATCHES OF 1 T0 32 OPERATIONS
class Protocol
  include Debug
  include Cloning
  include OpenTronsAq

  REACTION_VOLUME = 30.0
    
  TOTAL_THERMOCYCLERS = 1

  BLOCKS_PER_THERMOCYCLER = 3
  ZONES_PER_BLOCK = 2
  REACTIONS_PER_ZONE = 16

  def main
    current_taken_items = []
    input_volumes = {"Insert" => (REACTION_VOLUME / 10.0).round(2), "Vector" => (REACTION_VOLUME / 30.0).round(2), "Gibson Master Mix" => (REACTION_VOLUME / 2.0).round(2)}
    output_volumes = {"Gibson Reaction Product" => (REACTION_VOLUME*0.95 - 2.0).round}
    
    data = show do
        title "Check if at least one thermocycler block is available"
        warning "Warning: Selecting \"No\" will abort the protocol."
        select [ "Yes", "No"], var: "choice", label: "Is there at least 1 thermocycler block currently available?", default: 0
    end

    if data[:choice] == "No"
        show do
            title "Number of reactions scheduled exceeds available capacity."
            note "Number of reactions scheduled exceeds available capacity."
            warning "Aborting protocol. Please check with the lab manager for further instructions."
        end
        return {}
    end
    
    show do
        title "Keep all items on ice"
        warning "Note: All items used in this protocol should be kept on ice (or thawed at room temperature then immediately transfered to ice)."
    end
    
    operations.add_static_inputs "Gibson Master Mix", "HiFi MM (2x)", "Enzyme Stock"
    check_user_inputs ["Insert", "Vector"], input_volumes, current_taken_items
    assign_input_items ["Gibson Master Mix"], input_volumes, current_taken_items
    return {} if check_for_errors
    operations.sort_by! {|op| [op.input("Vector").item.id, op.input_array("Insert").items[0].id]}
    
    operations.running.each do |op|
        water_to_add = (REACTION_VOLUME - input_volumes["Insert"]*op.input_array("Insert").items.count - input_volumes["Vector"] - input_volumes["Gibson Master Mix"]).round(2)
        if water_to_add > 0.000001
            op.temporary[:water_to_add] = water_to_add
        else
            op.error :volume_error, "Water to add evaluated to negative value, possibly due to too many inputs."
        end
    end
    
    robust_make ["Gibson Reaction Product"], current_taken_items
    
    robust_take_inputs ["Insert", "Vector"], current_taken_items, interactive: true
    
    ot2_choice = show do
        title "Select execution method"
        select ["Yes", "No"], var: "ot2", label: "Is the OT2 robot available?"
    end
    
    if ot2_choice[:ot2] == "Yes"
        
        prot = OTAqProtocol.new
        
        prot.add_labware_definition('24-well-1.5ml-rack')
        
        water_container = prot.labware.load('point', '1', 'Water')
        water = prot.dummy_item "DI Water"
        prot.assign_wells [water], [water_container.wells(0)]
        
        td = prot.modules.load('tempdeck', '10')
        temp_deck_tubes = prot.labware.load('PCR-strip-tall', '10', 'Temp deck w/ PCR tubes')
        
        tip_racks = []
        tip_racks << prot.labware.load('tiprack-10ul', '3')
        tip_racks << prot.labware.load('tiprack-10ul', '6')
        p10 = prot.instruments.P10_Single(mount: 'right', tip_racks: tip_racks)
        
        prot.assign_wells operations.running.map{|op| op.output("Gibson Reaction Product").item}, temp_deck_tubes.wells[0..operations.running.count-1]
        
        prot.assign_wells operations.running.map{|op| op.input("Gibson Master Mix").item}.uniq
        prot.assign_wells operations.running.map{|op| op.input_array("Insert").items}.flatten.uniq
        prot.assign_wells operations.running.map{|op| op.input("Vector").item}.uniq
        
        td.set_temperature(4)
        
        # Add master mix
        p10.pick_up_tip
        operations.running.each do |op|
            mm_to_add = input_volumes["Gibson Master Mix"]
            while mm_to_add > 10
                p10.aspirate(10, prot.find_well(op.input("Gibson Master Mix").item).bottom(0))
                p10.dispense(10, prot.find_well(op.output("Gibson Reaction Product").item).bottom(0))
                mm_to_add -= 10
            end
            p10.aspirate(mm_to_add, prot.find_well(op.input("Gibson Master Mix").item).bottom(0))
            p10.dispense(mm_to_add, prot.find_well(op.output("Gibson Reaction Product").item).bottom(0))
        end
        p10.drop_tip
        
        # Add water
        p10.pick_up_tip
        operations.running.each do |op|
            while op.temporary[:water_to_add] > 10
                p10.aspirate(10, prot.find_well(water))
                p10.dispense(10, prot.find_well(op.output("Gibson Reaction Product").item).bottom(0))
                op.temporary[:water_to_add] -= 10
            end
            p10.aspirate(op.temporary[:water_to_add], prot.find_well(water))
            p10.dispense(op.temporary[:water_to_add], prot.find_well(op.output("Gibson Reaction Product").item))
        end
        p10.drop_tip
        
        # Add other reagents
        operations.running.each do |op|
            p10.pick_up_tip
            p10.aspirate(input_volumes["Vector"], prot.find_well(op.input("Vector").item).bottom(0))
            p10.dispense(input_volumes["Vector"], prot.find_well(op.output("Gibson Reaction Product").item).bottom(0))
            p10.drop_tip
            
            op.input_array("Insert").items.each do |insert_item|
                p10.pick_up_tip
                p10.aspirate(input_volumes["Insert"], prot.find_well(insert_item).bottom(0))
                p10.dispense(input_volumes["Insert"], prot.find_well(op.output("Gibson Reaction Product").item).bottom(0))
                p10.drop_tip
            end
        end
        
        td.set_temperature(50)
        p10.delay(3600)
        
        td.set_temperature(4)
        
        robust_take_inputs ["Gibson Master Mix" "Vector", "Insert"], current_taken_items, interactive: true
        
        show do
            title "Prepare output PCR tubes."
            note "Get out #{operations.running.count} new PCR tubes and label with the following IDs: #{operations.running.map {|op| op.output("Gibson Reaction Product").item.id}.to_sentence}"
        end
        
        run_protocol prot
        
        show do
           title "Set timer for removing inputs"
           check "Set a timer for 20 min, after which the robot should be done pipetting and you can remove and store input items (see following slide)."
           timer initial: { hours: 0, minutes: 20, seconds: 0}
           check "Do NOT remove the output items (small PCR tubes on temperature block)."
        end
        
        robust_release_inputs ["Gibson Master Mix" "Vector", "Insert"], current_taken_items, interactive: true
        
        show do
            title "Set timer for storing outputs"
            check "Set a timer for 1 hr, after which the reactions should be done incubating. At this point, you must reset the run to innactivate the temp block, and then store the output items (see following slides)."
           timer initial: { hours: 2, minutes: 0, seconds: 0}
        end

    else
        
        show do
            title "Add reagents to reaction tubes"
            note "Get out #{operations.running.count} new PCR tubes. Label and add reagents to tubes according to the following table:"
            table operations.start_table
            .output_item("Gibson Reaction Product")
            .custom_column(heading: "Water to add", checkable: true) { |op| "#{op.temporary[:water_to_add]} µl of water"}
            .custom_column(heading: "Vector to add", checkable: true) { |op| "#{input_volumes["Vector"]} µl of #{op.input("Vector").item.id}"}
            .custom_column(heading: "Inserts to add", checkable: true) { |op| op.input_array("Insert").items.each_with_index.map {|insert, i| "#{input_volumes["Insert"]} µl of #{insert.id}"}.join(", ")}
            .end_table
        end
        
        robust_release_inputs ["Insert", "Vector"], current_taken_items, interactive: true
        
        robust_take_inputs ["Gibson Master Mix"], current_taken_items, interactive: true
        
        show do
            title "Add #{operations.running[0].input("Gibson Master Mix").sample.name} to reaction tubes"
            note "Add #{operations.running[0].input("Gibson Master Mix").sample.name} to reaction tubes according to the following table:"
            table operations.start_table
            .output_item("Gibson Reaction Product")
            .custom_column(heading: "Gibson Master Mix", checkable: true) { |op| "#{input_volumes["Gibson Master Mix"]} µl of #{op.input("Gibson Master Mix").item.id} (#{op.input("Gibson Master Mix").sample.name})"}
            .end_table
        end
        
        robust_release_inputs ["Gibson Master Mix"], current_taken_items, interactive: true
        
    
        all_block_names = []
        TOTAL_THERMOCYCLERS.times do |tc_number|
            BLOCKS_PER_THERMOCYCLER.times do |block_number|
                all_block_names << "Thermocycler " + (tc_number+1).to_s + ", Block " + (block_number+1).to_s
            end
        end
        
        data = show {
            title "Select block of thermocycler"
            note "Please select the thermocycler block you would like to use."
            select all_block_names, var: "choice", label: "Block(s) #", default: 0
            }
        block_name = data[:choice]
        
        table_matrix = Array.new {Array.new}
        table_matrix[0] = ["Zone in #{block_name}", "Gibson Reaction Product Item IDs" ]
        table_matrix[1] = ["Zone 1", []]
        table_matrix[2] = ["Zone 2", []]
        operations.running.each_with_index do |op, i|
            if i < 16
                table_matrix[1][1] << op.output("Gibson Reaction Product").item.id.to_s
                op.output("Gibson Reaction Product").item.move (block_name + ", Zone 1")
            else
                table_matrix[2][1] << op.output("Gibson Reaction Product").item.id.to_s
                op.output("Gibson Reaction Product").item.move (block_name + ", Zone 2")
            end
        end
        table_matrix[1][1] = table_matrix[1][1].join(", ")
        table_matrix[2][1] = table_matrix[2][1].join(", ")
        
        show do
            title "Place Gibson reactions into #{block_name}"
            note "Place Gibson reactions into #{block_name} according to the following table:"
            table table_matrix
        end
    
        show do
            title "Set up PCR cycle for #{block_name}"
            bullet "Select the circular \"Set Up Run\" button corresponding to #{block_name}"
            bullet "Select \"Open Method\", then \"GIBSON\" (located in \"Mary\" folder)"
            bullet "Select \"Verify Block\", and \"Start Run\""
        end
    end
    
    store_outputs_with_volumes output_volumes, current_taken_items, interactive: true
    return {}
  end
end
