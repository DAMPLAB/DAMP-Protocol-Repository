needs "Standard Libs/Debug Lib"
needs "Cloning Libs/Cloning"

class Protocol
    
    include Cloning
    include Debug
    def overnight_steps(op, ot)
    
        op.retrieve
        
        show do
            title "Label and load overnight tubes"
            log_info "culture vol", op[0].temporary[:culture_vol]
            check "Collect #{op.select{|o| o.temporary[:culture_vol] < 1500}.length} 2mL tubes" if op.select{|o| o.temporary[:culture_vol] < 1500}.any?
            check "Collect #{op.select{|o| o.temporary[:culture_vol] > 1500}.length} 14mL tubes" if op.select{|o| o.temporary[:culture_vol] > 1500}.any?
            check "Write the overnight id on the corresponding container and load with the correct media type. Ampicilin and Carbenicilin can be used on place of each other."
            table op.start_table
              .output_item("Overnight", checkable: true)
              .custom_column(heading: "Media") { |op| "LB+" + op.input("Plasmid").child_sample.properties["Bacterial Marker"][0,3].upcase }
              .custom_column(heading: "Media Volume") { |op| (op.temporary[:culture_vol]/1000).to_s + " mL"}
              .end_table
        end

        show {
            title "Inoculation from #{ot}"
            note "Use sterile tips located on 'Inoculation Tips' drawer to inoculate colonies from plate into cultures according to the following table." if ot == "Checked E coli Plate of Plasmid"
            check "Mark each colony on the plate with corresponding overnight id. If the same plate id appears more than once in the table, inoculate different isolated colonies on that plate." if ot == "Checked E coli Plate of Plasmid"
            check "Use sterile tips located on 'Inoculation Tips' drawer to inoculate cells from glycerol stock into the cultures according to the following table." if ot == "Plasmid Glycerol Stock"
            table op.start_table
              .output_item("Overnight")
              .input_item("Plasmid", checkable: true)
              .end_table
        }
    end

  def main
    operations.sort_by! {|op| op.input("Plasmid").item.id}

    operations.each do |op|
        unless op.input("Plasmid").child_sample.properties["Bacterial Marker"]
            if debug && rand(2) == 1
              op.input("Plasmid").child_sample.set_property "Bacterial Marker", "Amp"
            else
              op.error :missing_marker, "No bacterial marker associated with plasmid"
            end
        end
    end
    return {} if check_for_errors
    
    operations.running.make
    
    #strip non-integers from volume parameter and associate with outputs
    operations.running.each do |op|
        op.temporary[:culture_vol] = (op.input("Culture Volume (mL)").val.delete('^0-9').to_i)*1000.0
        op.output("Overnight").item.associate(:volume, op.temporary[:culture_vol])
        op.output("Overnight").item.save
    end
    
    p_ot = ObjectType.where(name: "Checked E coli Plate of Plasmid").first 
    
    raise "Could not find object type 'Checked E coli Plate of Plasmid'" unless p_ot
    
    plate_inputs = operations.running.select { |op| op.input("Plasmid").item.object_type_id == p_ot.id }
    
    g_ot = ObjectType.where(name: "Plasmid Glycerol Stock").first 
    
    raise "Could not find object type 'Plasmid Glycerol Stock'" unless g_ot 
    
    glycerol_stock_inputs = operations.running.select { |op| op.input("Plasmid").item.object_type_id == g_ot.id }
    
    volumes_of_lb_to_mix = Hash.new(0.0)
    operations.running.each do |op|
        key = op.input("Plasmid").child_sample.properties["Bacterial Marker"][0,3].upcase
        volumes_of_lb_to_mix[key.to_s] += (op.output("Overnight").item.get(:volume) / 1000.0).round
    end

    table_matrix = Array.new(volumes_of_lb_to_mix.count + 1) {Array.new(2) {""}}
    table_matrix[0] = ["LB volume", "Antibiotic (volume)"]
    volumes_of_lb_to_mix.each_with_index do |(ab_name, volume), index|
        table_matrix[index+1] = [{content: ((volume * 1.05 + 1).ceil.to_s + " mL"), check: true}, {content: (ab_name.to_s + " (" + (volume * 1.05 + 1).ceil.to_s + "µl)"), check: true}]
    end

    show do
        title "Prepare the following LB + antibiotic solutions"
        check "Turn on bunsen burner."
        check "Confirm that the LB media stock is sterile (should not be cloudy or have floating particles)."
        note "Mix the following amounts of LB + antibiotic solutions in 50 mL plastic conical tubes. Label with the name of the antibiotic added."
        note "You can find the antibiotic in M20S, box 'Antibiotics'. Ampicilin and Carbenicilin can be used on place of each other."
        table table_matrix
        warning "Remember to keep the LB stock sterile at all times."
        check "Return the antibiotic solution(s) to the freezer."
    end
    
    overnight_steps plate_inputs, "Checked E coli Plate of Plasmid" if plate_inputs.any?
    overnight_steps glycerol_stock_inputs, "Plasmid Glycerol Stock" if glycerol_stock_inputs.any?
    
    show do
        title "Ensure gas is turned off"
        warning "Turn off the gas by turning the handle to a 90 degree angle. Listen for any signs of leakage."
    end
    
    # Associate input id with data for overnight.
    operations.running.each do |op|
        op.set_output_data "Overnight", :from, op.input("Plasmid").item.id
    end
    
    operations.running.each do |op|
        op.output("Overnight").child_item.move "37 C shaker incubator"
    end
    
    operations.store
    
    show do
        title "Turn on shaking incubator"
        check "Press start on the shaking incubator. Ensure it is set to ~225 RPM and 37C"
    end
    
    return {}

  end 
  
end
