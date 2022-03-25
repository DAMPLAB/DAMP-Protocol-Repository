class Protocol

  def main

    operations.retrieve.make
    
    fragments = {}
    conc_Table = []
    
    # Prepare PCR Machine 
    show do
        title "Prepare bench"
        check "If the PCR machine is off (no numbers displayed), turn it on using the ON/STDBY button - the button will be on the back of the machine."
        check "Select MoGib program and confirm…"
        bullet "37oC for 15 minutes"
        bullet "50oC for 60 minutes"
        bullet "4oC hold"
        check "Confirm that the lid heat is set up to 105oC"
        image "SelectTheProgramOnThermocycler.jpg"

    end
    
    # Thaw 2x Gibson Mix
    show do
        title "Thaw 2x Gibson Mix"
        check "Thaw 2x Gibson Mix on the bench."
        check "Get an ice bucket filled with ice."
        check "As soon as the Gibson mix is thawed, place it on ice."
        image "moclolevel1/moclol1_Picture1.jpg"
    end
    
    # Readying the PmeI Restriction Enzyme
    show do
        title "Readying the PmeI Restriction Enzyme"
        my_ops = operations.running.select do |op|
            note "Place #{op.input("PmeI").sample.name} in a -20oC ice box, on the bench"
        end
        image "moclolevel1/moclol1_Picture2.jpg"
    end
    
    show do
      title "Enter the concentration and base pair size of the DNA stock"
      
      note "We're going to dilute this sample to 20 fmol/ul by calculating the amount of water you need to add to each sample - our software will do the calculation for you."
      note "Enter the concentration of the DNA samples that should be listed on the DNA samples' tubes - the unit value needs to be in ng/ul. "
      
      # table for fragment concentration & bp
      frag_table = [["DNA Fragment", "Concentration (ng/ul)", "Base Pair Size"]]
      operations.each do |op|
        op.input_array("DNA Fragment").each do |frag|
            frag_table.push [
                { content: frag.sample.name },
                { type: "number", operation_id: op.id, key: "conc_#{frag.id}".to_sym, default: 40 },
                { type: "number", operation_id: op.id, key: "bp_#{frag.id}".to_sym, default: 50 }
            ]
        end
      end
      
      table frag_table
    end
    
    show do
      title "Dilute the DNA in a separate tube"
      
      note "Use the table values below to dilute the DNA"
      
        conc_Table = [
            ["DNA Fragment", "Conc. (ng/ul)", "Conc. (ug/ul)", "Size (bp)", 
            "Molecular Weight of a Base Pair", "1/N where N is base pairs", "pMol DNA/uL", "fmol DNA/uL",
            "DNA to add", "Water to add", "uL to get 40 fmol", "fmol DNA"]
        ]
        operations.running.each do |op|
            fragments = op.input_array("DNA Fragment")
            
            fragments.each do |f|
                conc_ug = op.temporary["conc_#{f.id}".to_sym]/1000.0
                bp_weight = (10**6)/(660)
                one_over_n = 1.0/op.temporary["bp_#{f.id}".to_sym]
                pMol = (conc_ug * bp_weight * one_over_n).round(3)
                fMol = op.temporary["conc_#{f.id}".to_sym] * bp_weight * one_over_n
                dna_to_add = (400.0/((op.temporary["conc_#{f.id}".to_sym]) * bp_weight * (one_over_n))).round(1)
                water_to_add = (20.0 - (400.0/(((op.temporary["conc_#{f.id}".to_sym] / 1000.0) * bp_weight * one_over_n) * 1000.0))).round(1)
                ul_to_forty = 1.0
                fmolDNA = 40.0
                
                conc_Table.push([f.sample.name, op.temporary["conc_#{f.id}".to_sym], conc_ug, op.temporary["bp_#{f.id}".to_sym],
                bp_weight, one_over_n, pMol, fMol, 
                dna_to_add, water_to_add, ul_to_forty, fmolDNA])
            end
        end
        
        table conc_Table
        
        warning "Remember to dilute the DNA in a tube separate from the one that is carrying the DNA"
    end
    

    
    # PCR Plate or Tube
    show do
        title "Start the Reaction"
        check "Retrieve a PCR tube/plate for the reaction we're about to perform"
        note "Add the following to the reaction tube/well to make a total of 10 ul of solution:"
        
        operations.running.select do |op|
            fragments.each do |f|
                bullet "1ul of #{f.sample.name}"
            end
            bullet "5ul of #{op.input("2x Gibson Mix").sample.name}"
            bullet "1ul of #{op.input("PmeI").sample.name}"
            bullet "#{10-(fragments.length*1)-6.0}ul of autoclaved dH2O"
        end
        image "moclolevel1/moclol1_Picture3.jpg"
    end

    # Display table to tech
    show do
        title "Centrifuge the Reaction"
        warning "Close PCR tubes or seal the plate"
        check "Spin the PCR tubes or the PCR plate to collect the liquid at the bottom"
        image "moclolevel1/moclol1_Picture4.jpg"
    end
    
    operations.store(io: "input", interactive: true)
    
    # Display table to tech
    show do
        title "Incubate the reaction at the PCR machine"
        timer initial: { hours: 1, minutes: 15, seconds: 0}
        warning "After clicking OK from this screen, the protocol will end and you will be directed on where to return the items to their freezer location."
        image "moclolevel1/moclol1_Picture5.jpg"
    end
    
    operations.store(io: "output", interactive: true)
   
    
    return {}
    
  end

end
