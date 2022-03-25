needs "Standard Libs/Debug Lib"
needs "Standard Libs/Ordering Lib"
needs "Cloning Libs/Cloning"
needs "Cloning Libs/OpenTronsAq"

class Protocol
  include Debug
  include Cloning
  include Ordering
  include OpenTronsAq
  
  require 'date'
  
  PLASMID = "Plasmid"
  PRIMER = "Sequencing Primer"
  REACTION_VOLUME = 15
  STRIPWELL_LENGTH = 8

  def main
    current_taken_items = []
    # Remember to add volume information to input and output object types (and concentration data where applicable).
    input_volumes = {PLASMID => 10, PRIMER => 1}

    check_user_inputs [PLASMID, PRIMER], input_volumes, current_taken_items
    return {} if check_for_errors
    operations.sort_by! {|op| op.input(PLASMID).item.id}

    operations.running.each do |op|
        water_to_add = REACTION_VOLUME - input_volumes[PLASMID] - input_volumes[PRIMER]
        op.temporary[:water_to_add] = water_to_add
    end

    robust_take_inputs [PLASMID, PRIMER], current_taken_items, interactive: true

    operations.running.each_with_index do |op, i|
        op.pass(PLASMID)
        op.temporary[:well_number] = i + 1
    end

    show do
      title "Prepare stripwells for sequencing reaction"
      (operations.running.count.to_f / STRIPWELL_LENGTH).ceil.times do |i|
        check "Prepare a #{STRIPWELL_LENGTH}-well stripwell, and label the first well with #{i * STRIPWELL_LENGTH + 1} and the last well with #{i * STRIPWELL_LENGTH + STRIPWELL_LENGTH}"
      end
    end

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

        prot.assign_wells operations.running.map{|op| op.input(PLASMID).item}.uniq
        prot.assign_wells operations.running.map{|op| op.input(PRIMER).item}.uniq

        operations.running.each_with_index do |op, i|
            op.temporary[:dummy_tube] = prot.dummy_item "Seq Reaction #{i + 1}"
            
            # adding extra rows to accomodate tube caps.
            prot.assign_wells [op.temporary[:dummy_tube]], [temp_deck_tubes.wells(i + 8 * (i / 8))]
        end

        # Add templates
        operations.running.each do |op|
            p10.pick_up_tip
            p10.aspirate(input_volumes[PLASMID], prot.find_well(op.input(PLASMID).item).bottom(0))
            p10.dispense(input_volumes[PLASMID], prot.find_well(op.temporary[:dummy_tube]).bottom(0))
            p10.drop_tip
        end

        # Add water
        operations.running.each do |op|
            p10.pick_up_tip
            p10.aspirate(op.temporary[:water_to_add], water_container.wells(0).bottom(0))
            p10.dispense(op.temporary[:water_to_add], prot.find_well(op.temporary[:dummy_tube]).bottom(0))
            p10.drop_tip
        end

        # Add primers
        operations.running.each do |op|
            p10.pick_up_tip
            p10.aspirate(input_volumes[PRIMER], prot.find_well(op.input(PRIMER).item).bottom(0))
            p10.dispense(input_volumes[PRIMER], prot.find_well(op.temporary[:dummy_tube]).bottom(0))
            
            # Mix
            p10.aspirate(input_volumes[PLASMID], prot.find_well(op.temporary[:dummy_tube]).bottom(0))
            p10.dispense(input_volumes[PLASMID], prot.find_well(op.temporary[:dummy_tube]).bottom(0))
            p10.aspirate(input_volumes[PLASMID], prot.find_well(op.temporary[:dummy_tube]).bottom(0))
            p10.dispense(input_volumes[PLASMID], prot.find_well(op.temporary[:dummy_tube]).bottom(0))
            p10.drop_tip
        end

        run_protocol prot

    else

        show do
          title "Load stripwells with DI water"
          note "Load stripwells with DI water"
          table operations.start_table
            .custom_column(heading: "Well number") {|op| op.temporary[:well_number]}
            .custom_column(heading: "Water to add") { |op| {content: "#{op.temporary[:water_to_add]} µl of water", check: true} }
            .end_table
        end

        show do
          title "Load stripwells with DNA template"
          note "Load stripwells with DNA template"
          table operations.start_table
            .custom_column(heading: "Well number") {|op| op.temporary[:well_number]}
            .custom_column(heading: "DNA template to add") { |op| {content: "#{input_volumes[PLASMID]} µl of #{op.input(PLASMID).item.id}", check: true} }
            .end_table
        end

        show do
          title "Load stripwells with primer"
          note "Load stripwells with primer"
          table operations.start_table
            .custom_column(heading: "Well number") {|op| op.temporary[:well_number]}
            .custom_column(heading: "Primer to add") { |op| {content: "#{input_volumes[PRIMER]} µl of #{op.input(PRIMER).item.id}", check: true} }
            .end_table
        end
    end

    robust_release_inputs [PLASMID, PRIMER], current_taken_items, interactive: true

    table_matrix = Array.new() {Array.new()}
    operations.running.each_with_index do |op, i|
        table_matrix[i] = [
            op.input(PLASMID).item.id.to_s,
            op.input(PLASMID).sample.sample_type.name == "Plasmid" ? "Plasmid" : "Purified PCR",
            op.input(PLASMID).sample.properties["Length"].to_s,
            "80",
            "Yes",
            op.input(PRIMER).sample.id.to_s,
            "1.67",
            op.input(PLASMID).item.get(:concentration_keyword) == "STANDARD" ? "None" : "Hairpin"
            ]
    end

    nickname = "Job #{JobAssociation.where(operation_id: operations[0].id).first.id}"

    # create Quintara order
    genewiz = show do
      title "Create a Quintara order"
      check "Go the <a href='http://www.quintarabio.com/' target='_blank'>QUINTARA website</a>, log in with lab account (Username: damplab@bu.edu, Password: cidar01)."
      #check "In 'My Sanger Sequencing', choose 'Excel File Upload', 'Choose File', 'Upload', #{operations.running.running.length} samples."
      #check "Confirm that the information, in general, is correct."
      check "Click \"Order\" (top navigation bar) -> \"Sequencing Order Form\" (top link in menu on the lefthand side)."
      check "Paste in the following information:"
      table table_matrix
      check "TYPE (do not copy paste) the following into the \"Nick Name Order\" box: #{nickname}"
      check "Click \"Order\" -> \"Confirm\" and enter the Quintara Order ID below."
      get "text", var: "tracking_num", label: "Enter the Quintara Order ID", default: "3756939"
      check "Get out a zip-lock bag and label in black marker with the Quintara Order ID."
    end

    # store stripwells in dropbox
    show {
      title "Put all stripwells in the Quintara dropbox"
      check "Cap all of the stripwells."
      check "Put the stripwells into the zip-lock bag."
      check "Ensure that the bag is sealed, and put it into the Quintara dropbox."
    }

    # associate order data with plasmid items
    #operations.running.each do |op|
    #  op.set_output_data PLASMID, :tracking_num, genewiz[:tracking_num]
    #end
    
    place_seq_order ["Quintara", operations.running.count, operations.running.count*4, Date.today.strftime('%m/%d/%Y'), "Aquarium", nickname, "DLN"]

    return {}

  end

end

