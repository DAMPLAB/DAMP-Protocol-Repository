pneeds "Standard Libs/Debug Lib"
needs "Cloning Libs/Cloning"
class Protocol
  include Debug
  include Cloning
  
  PERCENTAGE = 1.0
  LADDER_LANES_PER_GEL = 1
  # Define gel box types. Can be updated as new gel boxes are purchased. Only one comb configuration is currently allowed per gel box type.
  # "count" designates the total number of gel boxes of this type available in this lab.
  # Volumes should be set at 1.2x desired volume to account for evaporation during agarose preparation
  GEL_BOX_TYPES = [
    { count: 1, description: "EasyCast B1A", lanes_per_gel: 10, volume: 56.0*1.2, comb_description: "B1A-10 (10 well comb, purple). Note that the comb is double sided and you MUST use the side with thicker teeth."},
    { count: 1, description: "EasyCast B2", lanes_per_gel: 20, volume: 168.0*1.2, comb_description: "B2-20 (20 well comb, green). Note that the comb is double sided and you MUST use the side with thicker teeth."}
    ]
    
    
  def main
    current_taken_items = []
    # Remember to add volume information to input and output object types (and concentration data where applicable).
    
    show do
        title "Keep all items on ice"
        warning "Note: All items used in this protocol should be kept on ice (or thawed at room temperature then immediately transfered to ice)."
    end
    
    operations.add_static_inputs "Loading Dye", "6X Loading Dye", "Screw Cap Tube Stock"
    operations.add_static_inputs "Ladder", "2-Log DNA Ladder", "Ladder Stock"
    operations.add_static_inputs "DpnI", "DpnI", "Enzyme Stock"
    operations.sort_by! {|op| op.input("Impure DNA").item.id}
    
    gel_box_types_by_size = GEL_BOX_TYPES.sort_by { |box_type| box_type[:lanes_per_gel] }
    gel_box_types_by_size.each_index do |index|
        gel_box_types_by_size[index][:count_confirmed] = false
        gel_box_types_by_size[index][:lanes_per_gel] -= LADDER_LANES_PER_GEL
    end
    
    choices_confirmed = false
    # Algorithm which decides which gel boxes to use and confirms box availability with the tech.
    while !choices_confirmed
        lanes_remaining = operations.running.count
        # if there are not enough gel boxes to do this, abort
        total_lanes_available = 0
        gel_box_types_by_size.each do |box_type|
            total_lanes_available += box_type[:count]*box_type[:lanes_per_gel]
        end
        if total_lanes_available < lanes_remaining
            show do
                title "Not enough gel boxes available"
                warning "There are not enough gel boxes available to perform the selected operations. The protocol will now abort. Check with lab manager for next steps."
            end
            return {}
        end
        
        box_counts_required = Array.new(GEL_BOX_TYPES.count, 0)
        while lanes_remaining > 0
            # Iterate through, skipping if box_counts_required for that box type is already >= count. Stop at either first box that is big enough or the last box in the list. Reduce lanes remaining by size of box and add one to count required of that box. Continue until no lanes remaining.
            gel_box_types_by_size.each_with_index do |box_type, box_type_index|
                largest_available = -1
                gel_box_types_by_size.each_with_index do |elem, index|
                    if elem[:count] > box_counts_required[index]
                        largest_available = index
                    end
                end
                if box_counts_required[box_type_index] < box_type[:count] && lanes_remaining > 0 && (box_type[:lanes_per_gel] >= lanes_remaining || box_type_index == largest_available)
                    box_counts_required[box_type_index] += 1
                    lanes_remaining = [0, lanes_remaining-box_type[:lanes_per_gel]].max
                end
            end
        end
        # Check with user if there are enough boxes of different types, adjusting :count for each type to reflect actual availability. Skip any that the tech has already been asked about.
        choices_confirmed = true
        box_counts_required.each_with_index do |count_required, box_type_index|
            if count_required > 0 && !gel_box_types_by_size[box_type_index][:count_confirmed]
                options = Array.new(gel_box_types_by_size[box_type_index][:count]+1){|i| (i).to_s}
                data = show do
                    title "Indicate number of available gel boxes"
                    select options, var: "number_available", label: "How many gel boxes of type #{gel_box_types_by_size[box_type_index][:description]} are currently available?", default: gel_box_types_by_size[box_type_index][:count]
                end
                gel_box_types_by_size[box_type_index][:count] = data[:number_available].to_i
                gel_box_types_by_size[box_type_index][:count_confirmed] = true
                if data[:number_available].to_i < count_required
                    choices_confirmed = false
                end
            end
        end
    end
    box_counts_required_run = box_counts_required
    
    pcr_input_ops = operations.running.select{|op| op.input("Impure DNA").object_type.name.include?("PCR")}
    log_info "box_counts_required", box_counts_required
    log_info "box_counts_required.sum", box_counts_required.sum
    log_info "operations.running.count.to_f", operations.running.count.to_f
    log_info "(10.0*box_counts_required.sum/operations.running.count.to_f).round(2)", (10.0*box_counts_required.sum/operations.running.count.to_f).round(2)
    input_volumes = {"Impure DNA" => 5.0, "Loading Dye" => 1.0, "Ladder" => (5.0*box_counts_required.sum/operations.running.count.to_f).round(2), "DpnI" => (pcr_input_ops.count / operations.running.count.to_f).round(2) }
    check_user_inputs ["Impure DNA"], input_volumes, current_taken_items
    assign_input_items ["Loading Dye", "Ladder", "DpnI"], input_volumes, current_taken_items
    return {} if check_for_errors
    
    if pcr_input_ops.any?
        robust_take_inputs ["Impure DNA", "DpnI"], current_taken_items, interactive: true
    
        show do
            title "Add DpnI to PCR input items"
            note "Add DpnI to PCR input items according to the following table:"
            table pcr_input_ops.start_table
            .input_item("Impure DNA")
            .custom_column(heading: "DpnI to add") {|op| {content: "1 µl of #{op.input("DpnI").item}", check: true} }
            .end_table
        end
        
        pcr_input_ops.running.each do |op|
            op.input("Impure DNA").item.move("37C incubator")
            op.input("Impure DNA").item.save
        end
    
        robust_release_inputs ["Impure DNA", "DpnI"], current_taken_items, interactive: true
    end
    
    lanes_made = 0
    box_counts_required.each_with_index do |count_required, box_type_index|
        volume = gel_box_types_by_size[box_type_index][:volume]
        comb_description = gel_box_types_by_size[box_type_index][:comb_description]
        description = gel_box_types_by_size[box_type_index][:description]
        mass = ((PERCENTAGE / 100.0) * volume).round(2)
        while count_required > 0
            current_gel_ops = operations.running[lanes_made..[operations.running.count - 1, lanes_made + gel_box_types_by_size[box_type_index][:lanes_per_gel] - 1].min]
            lanes_made += [operations.running.count - lanes_made, gel_box_types_by_size[box_type_index][:lanes_per_gel]].min
            show do
                title "Prepare agarose solution"
                check "Grab a flask that can hold at least #{(volume*2).ceil} mL."
                check "Using a digital scale, measure out #{mass} g of agarose powder and add it to the flask."
                check "Get a graduated cylinder from the cabinet. Measure and add #{volume} mL of 1X TAE to the flask containing agarose."
                check "Microwave flask for 60 seconds on high, then swirl."
                warning "Be careful! The hot agarose solution can split when mixed."
                check "Confirm that the agarose is fully dissolved by swirling gently and visually checking for undisolved specks of agarose. If necessary, microwave 30 more seconds on high. Repeat until dissolved. Carefully watch for signs of boiling and stop when necessary to prevent boiling over."
                warning "Wear high temperature protective gloves whenever handling this flask."
            end
            
            show do
                #Adding double SYBR safe for brighter band.
                title "Add #{(volume/10.0).round(2)} µL SYBR Safe"
                check "Pipette #{(volume/10.0).round(2)} µL of SYBR Safe (on shelf) directly into the molten agar (with pipette tip under the surface), then swirl to mix."
            end
            
            show do
                title "Prepare gel box for casting"
                check "Locate the following gel box: #{description}"
                check "Retrieve the following comb: #{comb_description}"
                image 'gel/comb.jpg'
                check "Turn the casting tray sideways in the gel box such that the orange rubber gasket is pressed tightly against the sides of the gel box. Insert the comb into the grooves at one end of the casting tray."
                image 'gel/setup.jpg'
                warning "Many combs have thick teeth on one side and thinner teeth on the other, double check that you are using the correct side"
            end
            
            show do
                title "Pour and label gel"
                check "Using a gel pouring autoclave glove, gently pour agarose from the flask into the casting tray."
                check "Pop any bubbles with a 10 µL pipet tip."
                check "Clean the flask with H2O and put it back on shelf."
                #check "Write id #{current_gel_ops.output_collections["Lane"][0].id.to_s} on piece of lab tape and affix it to the side of the gel box. You can find pen and tape on the shelf."
            end
            count_required -= 1
        end
    end
    
    show do
        title "Let the Agarose to Solidify"
        check "Leave the gel(s) at the bench to solidify, for 1 hour."
        timer initial: { hours: 1, minutes: 0, seconds: 0}
    end
    
    #operations.store(io: "output")
    #return {}
    
    ##################################################################################################
    robust_take_inputs ["Impure DNA", "Loading Dye", "Ladder"], current_taken_items, interactive: true
    
    show do
        title "Add 6X loading dye to input tubes"
        note "Add #{input_volumes["Loading Dye"]} µl of 6X loading dye to each 5 µl input tube according to the following table."
        table operations.running.start_table
        .input_item("Impure DNA")
        .custom_column(heading: "Loading dye to add", checkable: true) { |op| "#{input_volumes["Loading Dye"]} µl of #{op.input("Loading Dye").item.id} (#{op.input("Loading Dye").sample.name})"}
        .end_table
    end
    
    lanes_made = 0
    box_counts_required_run.each_with_index do |count_required, box_type_index|
        while count_required > 0
            current_gel_ops = operations[lanes_made..[operations.running.count - 1, lanes_made + gel_box_types_by_size[box_type_index][:lanes_per_gel] - 1].min]
            current_gel_ops.extend(OperationList)
            current_gel_ops.make
            
            table_matrix = Array.new(2) {Array.new(gel_box_types_by_size[box_type_index][:lanes_per_gel] + 2) {""}}
            table_matrix[0].each_index do |column|
                if column == 0
                    table_matrix[0][column] = "Well in gel"
                else
                    table_matrix[0][column] = column
                end
            end
            table_matrix[1].each_index do |column|
                if column == 0
                    table_matrix[1][column] = "Input item to load"
                elsif column == 1
                    table_matrix[1][column] = {content: "5 µl of #{current_gel_ops[0].input("Ladder").item.to_s} (#{current_gel_ops[0].input("Ladder").sample.name})", check: true}
                elsif column <= current_gel_ops.count+1
                    table_matrix[1][column] = {content: "1 µl of Loading dye and 5 µl of #{current_gel_ops[column-2].input("Impure DNA").item.to_s}", check: true}
                end
            end
            gel_id = current_gel_ops[0].output("Gel Lane").collection.id.to_s
            show do
                title "Prepare gel #{gel_id}"
                bullet "Insert a gel of type #{gel_box_types_by_size[box_type_index][:description]} into gel box with the comb near the NEGATIVE (black) electrode."
                bullet "Remove comb from gel."
                bullet "Confirm that the gel is covered with buffer. Add more 1X TAE to the gel box if necessary."
                bullet "Label gel by placing a piece of tape on the gel box with the gel ID: #{gel_id}"
            end
            show do
                title "Load gel #{gel_id}"
                note "Add ladder and DNA samples to the gel according to the following table:"
                table table_matrix
            end
            
            show do
                title "Start gel #{gel_id}"
                image 'gel/run.jpg'
                bullet "Carefully attach the gel box lid(s) to the gel box(es), being careful not to bump the samples out of the wells. Attach the red electrode to the red terminal of the power supply, and the black electrode to the neighboring black terminal. Set the voltage to 100 V."
                bullet "Hit the start button."
                bullet "Make sure the power supply is not erroring (no E* messages) and that there are bubbles emerging from the platinum wires in the bottom corners of the gel box."
            end
            lanes_made += [operations.running.count - lanes_made, gel_box_types_by_size[box_type_index][:lanes_per_gel]].min
            count_required -= 1
        end
    end
    
    #operations.running.each {|op| op.input("Impure DNA").item.mark_as_deleted}
    
    pcr_input_ops.running.each do |op|
        op.input("Impure DNA").item.move("DAMP Lab M20SRXS Box 0")
        op.input("Impure DNA").item.save
    end
    
    robust_release_inputs ["Impure DNA", "Loading Dye", "Ladder"], current_taken_items, interactive: true
    
    show do
        title "Set timer"
        check "Set a timer for 20 minutes. When the timer goes off, find a lab manager to check if the gel is finished."
        check "If the gel is finished, turn off the power supply. Extract fragment should be run immediately."
        timer initial: { hours: 0, minutes: 20, seconds: 0}
    end
    
    return {}
  end
end
