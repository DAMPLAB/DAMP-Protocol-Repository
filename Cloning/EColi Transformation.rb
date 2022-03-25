needs "Standard Libs/Debug Lib"
needs "Cloning Libs/Cloning"

class Protocol
  include Cloning
  include Debug

    
  #COMP_CELL = "Competent E. coli"
  PLASMID = "DNA to transform"
  PLATE = "Agar Plate"
  
  def main
    current_taken_items = []
    #Note: for inputs that are reactions, it will actually instruct the tech to add 5 ul, but this is ok because they are discarded afterwards anyway.
    input_volumes = {PLASMID => 1.0}
    
    show do
        title "Keep all items on ice"
        warning "Note: All items used in this protocol should be kept on ice (or thawed at room temperature then immediately transfered to ice)."
    end
    
    #comp_cell_sample = Sample.find_by_name("Alpha-Select Gold Efficiency")
    #comp_cell_items = comp_cell_sample.in("E coli Glycerol Stock")[0..operations.count-1]
    check_user_inputs [PLASMID], input_volumes, current_taken_items
    return {} if check_for_errors
    operations.sort_by! {|op| op.input(PLASMID).item.id}
    
    robust_make [PLATE], current_taken_items

   show do
        title "Readying Competent Cells"
        check "Fill a bucket with ice."
        check "Get out #{operations.running.count} competent cell items from the -80C freezer."
        warning "Thaw the tubes on ice for 5 minutes and flick to mix."
    end
    
    robust_take_inputs [PLASMID], current_taken_items, interactive: true
    
    show do
        title "Label 1.5 ml tubes"
        check "Get out #{operations.running.count} 1.5 ml tubes and label with IDs: #{operations.map{|op| op.output(PLATE).item}.to_sentence}"
        check "Add 10 µl of competent cells to each 1.5 ml tube."
        check "Discard empty competent cell tubes."
    end
    
    # Create the Reaction
    show do
        title "Add DNA to competent cells"
        note "Work close to a flame source while working with the competent cells."
        note  "Add DNA to 1.5 ml tubes containing competent cells according to the following table:"
        warning "Only use 1.0 uL of DNA when transforming Gibson Reaction Product."
        table operations.start_table
        .custom_column(heading: "ID") { |op| op.output(PLATE).item.id }
        .custom_column(heading: "DNA to add") {|op| {content:"#{(op.input(PLASMID).object_type.name.include? "Stock") ? 1.0 : 2.0} µl of #{op.input(PLASMID).item.id}", check: true}}
        #.custom_column(heading: "DNA to add")
            #if (op.input(MoClo Reaction Result).object_type.name.include? "Stock")
              #  {content:" 2.0 µl of #{op.input(PLASMID).item.id}", check: true}
            #elsif (op.input(PLASMID).object_type.name.include? "Stock")
              #  {content:" 1.0 µl of #{op.input(PLASMID).item.id}", check: true}
            #end
        .end_table
        check "Allow cells to sit on ice for 30 minutes after DNA is added."
        timer initial: { hours: 0, minutes: 30, seconds: 0}
        check "Turn the flame and gas line off."
    end
    
    ops_with_rxn_inputs = []
    ops_with_stock_inputs = []
    
    #operations.running.each do |op|
    #    if !(op.input(PLASMID).object_type.name.include? "Stock")
    #        op.input(PLASMID).item.mark_as_deleted
    #        ops_with_rxn_inputs << op
    #    else
    #        ops_with_stock_inputs << op
    #    end
    #end
    
    show do
        title "Discard reaction inputs"
        check "Discard some input items: #{ops_with_rxn_inputs.map{|op| op.input(PLASMID).item}.to_sentence}"
        warning "Do not discard input items: #{ops_with_stock_inputs.map{|op| op.input(PLASMID).item}.to_sentence}" if ops_with_stock_inputs.any?
    end if ops_with_rxn_inputs.any?
    
    robust_release_inputs [PLASMID], current_taken_items, interactive: true
    
    show do
        title "Heat shock"
        warning "Timing of this step is critical, only heat for 30 seconds then immediately return to ice!"
        check "Heat shock using a water bath at 42oC, for 30 seconds"
        timer initial: { hours: 0, minutes: 0, seconds: 30}
    end
    
    show do
        title "Let sit on ice again"
        check "Let the cells sit on ice again"
        timer initial: { hours: 0, minutes: 2, seconds: 0}
    end
    
    show do
        title "Add SOC"
        check "Take the cells off the ice"
        check "Open turn on bunsen burner and perform steps close to the flame."
        check "Confirm that SOC is not contaminated."
        check "Add 150 µl of SOC to each tube."
        check "Turn the flame off."
    end
    
    grouped_by_marker = operations.running.group_by { |op|
        op.input(PLASMID).sample.properties["Bacterial Marker"].upcase
    }
    plate_list = grouped_by_marker.map do |marker, ops|
        "#{ops.size} LB + #{marker} plates"
    end
    
    show do
        title "Incubate culture and label plates"
        check "Incubate cells in 37oC shaker, for 1 hour, shake at 225rpm"
        timer initial: { hours: 1, minutes: 0, seconds: 0}
        check "Retrieve agar plates with proper antibiotics (#{plate_list.to_sentence}) from the cold room and warm them up, upside down, in a 37oC incubator"
        check "Identify the plates on the bottom with the proper item ID."
        check "Also, write item IDs on the side (outside edge) of plates."
        table operations.start_table
        .output_item("Agar Plate")
        .custom_column(heading: "Marker") { |op| op.input(PLASMID).sample.properties["Bacterial Marker"].upcase }
        .end_table
    end
    
    show do
        title "Transfer cells to the plates"
        check "Turn on bunsen burner and work close to flame."
        check "Spin down 1.5 ml tubes of cells using the following settings:"
        centrifuge operations.running.count, 4000, 3
        check "Dump out liquid in 1.5 ml tubes of cells."
        check "Vortex tubes for 10 seconds."
        check "Transfer liquid from 1.5 ml tubes to the agar plates according to the following table:"
        table operations.start_table
        .output_item("Agar Plate")
        .custom_column(heading: "1.5 ml tube of cells") { |op| {content: "All of #{op.output(PLATE).item.id.to_s}", check: true} }
        .end_table
        check "Add approximately 20 transformation beads to the same side of each plate and roll around lightly to distribute liquid."
        check "Discard the beads in the Bead Waste Beaker."
        check "Discard the 1.5 ml tubes of cells."
    end
    
    #show do
        #title "Spin down cells and resuspend"
        #check "Spin down 1.5 ml tubes of cells using the following settings:"
        #centrifuge operations.running.count, 4000, 3
        #check "Dump out liquid in 1.5 ml tubes of cells."
        #check "Vortex tubes for 10 seconds."
    #end
    
    #show do
        #title "Transfer cells to one side of split plates"
        #check "Add the small amount of remaining liquid in the tubes to the other (unused) side of the split agar plates:"
        #table operations.start_table
        #.output_item("Agar Plate")
        #.custom_column(heading: "1.5 ml tube of cells") { |op| {content: "All of #{op.output(PLATE).item.id.to_s}", check: true} }
        #.end_table
        #check "Add approximately 10 transformation beads to the same side of each plate and roll around lightly to distribute liquid."
        #check "Discard the beads."
        #check "Discard the empty 1.5 ml tubes of cells."
    #end
    
    show do
        title "Incubate Cells"
        check "Let plates grow, upside down, in the 37oC incubator for 16 hours (overnight)."
        check "Confirm that plates are labelled with the date on the side (outside edge of plate) and the bottom of the plate."
        check "Turn off the flame and the gas line."
    end
    
    operations.running.each do |op|
        op.output(PLATE).item.move "37C incubator"
    end
    
    operations.running.store io:"output", interactive: true
    check_for_errors
    return {}
    
  end
 

end
