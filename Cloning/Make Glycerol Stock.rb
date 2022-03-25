needs "Standard Libs/Debug Lib"
needs "Cloning Libs/Cloning"

class Protocol
  include Cloning
  include Debug
  
  def main
    current_taken_items = []
    operations.sort_by! {|op| op.input("Overnight").item.id}

    robust_take_inputs ["Overnight"], current_taken_items, interactive: true
    
    # Verify whether each overnight has growth
    verify_growth = show do
        title "Check if overnights have growth"
        note "Choose No for the overnight that does not have growth and throw them away or put in the clean station."
        operations.each do |op|
            item = op.input("Overnight").item
            select ["Yes", "No"], var: "#{item.id}", label: "Does tube #{item.id} have growth?"
            item.mark_as_deleted
        end
    end
    
    # if no growth, error op  
    operations.each do |op|
        item = op.input("Overnight").item
        if verify_growth["#{item.id}".to_sym] == "No"
            op.error :no_growth, "The overnight has no growth."
        end
    end
    return {} if check_for_errors
    
    robust_make ["Glycerol Stock"], current_taken_items
    
    show do 
        title "Add glycerol to cryo tubes"
        check "Insert the small green cap into the top of the cryo tubes."
        check "Write the following IDs on the top and the side of cryo tubes: #{operations.running.map{|op| op.output("Glycerol Stock").item.id}.to_sentence}"
        check "Turn on bunsen burner and work close to flame."
        check "Pipette 900 µL of 50% glycerol (on shelf at Cell Culture Station) into each tube."
        warning "Do not contaminate the 50% glycerol solution."
    end
    
    show do 
        title "Add cultures to cryo tubes"
        note "Transfer from cultures to cryo tubes according to the following table:"
        table operations.start_table
            .output_item("Glycerol Stock")
            .custom_column(heading: "Culture item (input)") {|op| {content: "900 µl of #{op.input("Overnight").item.to_s}", check: true}}
            .end_table
    end
    
    show do 
        title "Vortex and Store"
        check "Close the flame"
        check "Vortex the tubes for 2 seconds."
        warning "Lable the storage location on the side of the cryo tubes before return the glycerol stock to the -80 freezer."
    end
    
    operations.running.each do |op|
        op.output("Glycerol Stock").item.associate(:from_culture, op.input("Overnight").item.id.to_s).save
    end
    
    robust_release operations.running.map{|op| op.output("Glycerol Stock").item}, current_taken_items, interactive: true
    
    show do
        title "Discard overnight cultures"
        check "Discard overnight cultures: #{operations.running.map{|op| op.input("Overnight").item}.to_sentence}"
    end
    check_for_errors
    return {}
  end
end
