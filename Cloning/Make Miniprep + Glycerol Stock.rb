needs "Standard Libs/Debug Lib"
needs "Cloning Libs/Cloning"

class Protocol
  include Cloning
  include Debug
  
  def main
    current_taken_items = []
    output_volumes = {"Plasmid" => 25}
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
        check "Write the following IDs on the top of the cryo tubes: #{operations.running.map{|op| op.output("Glycerol Stock").item.id}.to_sentence}"
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
    
    robust_make ["Plasmid"], current_taken_items
    
    show do
        title "Warm up water"
        check "Add #{(operations.running.count*output_volumes["Plasmid"]*1.5).round(2)} µl of water to a tube. Label it \"Water\" and place on the 55C heat block."
    end
    
    #transfer each overnight into 2 mL tube
    show do 
        title "Transfer Overnights into 2 mL Tubes and centrifuge"
        check "Get out #{operations.running.count} new 2 mL tubes and label from 1 to #{operations.running.count}"
        note "Transfer 1900 ul of liquid from each overnight culture to the corresponding 2 ml tubes according to the following chart:"
        index = 0
        table operations.running.start_table
            .input_item("Overnight")
            .custom_column(heading: "Tube Number") { {content: (index = index + 1), check: true} }
        .end_table
       centrifuge operations.running.count, 13000, 1
       check "Pour off the liquid into media waste, leaving only the solid pellet at the bottom of the tube."
       check "Repeat the previous steps until no liquid remains in the overnight culture tubes."
       check "Discard empty overnight culture tubes."
    end
    
    robust_release_inputs ["Overnight"], current_taken_items, interactive: false
    
    if debug
        operations.each do |op|
            op.input("Overnight").item.associate(:volume, Random.rand*10000)
        end
    end
    
    if operations.running.any? {|op| op.input("Overnight").item.get(:volume).to_i > 6000}
        large_vol_protocol = true
    else
        large_vol_protocol = false
    end
    
    # Resuspend in P1, P2, N3
    show do
        title "Resuspend in P1, P2, N3"
        note "This protocol uses the QIAprep Spin Miniprep Kit (blue box)."
        warning "The steps on this slide are time-sensitive. If you have more than ~6 tubes, break them up into multiple batches."
        check "Grab a timer."
        check "Check if all the buffers are prepared accordingly with vendor's instructions (check mark on top)."
        check "Grab P1 buffer from cold room."
        check "Add #{large_vol_protocol ? 500 : 250} µL of P1 into each tube and vortex on max setting for 20 seconds."
        check "Adjust the timer to 4 minutes."
        check "Add #{large_vol_protocol ? 500 : 250} µL of P2, start the timer, and gently invert 4-6 times to mix. Do not allow the lysis reaction to proceed for longer than 4 minutes!"
        check "When the timer goes off, pipette #{large_vol_protocol ? 700 : 350} µL of N3 into each tube and gently invert 4-6 times to mix, or until the mixture is colorless."
    end

    # Centrifuge and add to miniprep columns        
    show do
        title "Centrifuge and add to columns"
        centrifuge operations.running.count, 13000, 10
        check "Get out #{operations.running.count} new 1.5 mL tubes and label with the following IDs: #{operations.running.map{|op| op.output("Plasmid").item.id}.to_sentence}. These will be used later on in the protocol."
        check "Return buffer P1 to the cold room."
        check "Get out #{operations.running.count} blue miniprep spin columns and label with 1 to #{operations.running.count}."
    end
    
    show do
        warning "Do not discard the supernatant after spinning!"
        check "Remove the tubes from centrifuge and carefully apply 800 uL of the supernatant into the columns with the same numbers."
        warning "Be careful not to pipette the white solids."
        centrifuge operations.running.count, 13000, 1
        check "Discard the flow through into a miniprep waste container."
        if large_vol_protocol
            check "Transfer another 800 ul of supernatant from 2 ml tubes to columns."
            centrifuge operations.running.count, 13000, 1
            check "Discard the flow through into a miniprep waste container."
        end
        check "Discard the used 2 mL tubes."
    end
        
    # Spin and wash        
    show do 
        title "Continue with centrifugation steps"
        check "Add 500 µl of PB buffer to each column."
        centrifuge operations.running.count, 13000, 1
        check "Discard the flowthrough into a miniprep waste container."
        check "Add 750 µl of PE buffer to each column. Make sure the PE bottle that you are using has ethanol added (check mark on top)!"
        centrifuge operations.running.count, 13000, 1
        check "Remove the columns from the centrifuge and discard the flow through into a miniprep waste container."
        centrifuge operations.running.count, 13000, 1
    end
    
    show do 
        title "Transfer columns to 1.5 ml tubes"
        check "Remove the columns from the centrifuge"
        check "Inidividually take each column out of the flowthrough collector and place in 1.5 mL tubes according to the following chart. Discard the flowthrough collector."
        index = 0
        table operations.running.start_table 
            .output_item("Plasmid")
            .custom_column(heading: "Tube Number") { {content: (index = index + 1), check: true} }
            .end_table
    end
        
    show do
        title "Elute with water"
        check "Pipette 30 µl from the tube of warm water on the 55C heat block into the CENTER of each column without touching the membrane"
        check "Discard empty tube of water"
        check "Let the tubes sit on the bench for 1 minute"
        centrifuge operations.running.count, 13000, 1
        check "Discard the columns, but keep tubes and flowthrough!"
    end
    
    operations.running.each do |op|
        op.output("Plasmid").item.associate(:from_culture, op.input("Overnight").item.id.to_s).save
    end
    
    store_outputs_with_volumes output_volumes, current_taken_items, interactive: true
    check_for_errors
    return {}
  end
end
