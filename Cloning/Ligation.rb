needs "Cloning Libs/Cloning"
needs "Standard Libs/Debug Lib"

# Based on https://www.neb.com/protocols/0001/01/01/quick-ligation-protocol
# Optimized using data from https://www.ncbi.nlm.nih.gov/pmc/articles/PMC338853/pdf/nar00163-0413.pdf

class Protocol
    
  include Debug
  include Cloning
  REACTION_VOLUME = 20.0
  
  def main
      
    current_taken_items = []
    # Remember to add volume information to input and output object types (and concentration data where applicable).
    input_volumes = {"Insert" => (REACTION_VOLUME / 5.0).round(2), "Vector" => (REACTION_VOLUME / 20.0).round(2), "Ligase" => (REACTION_VOLUME / 20.0).round(2), "Buffer" => (REACTION_VOLUME / 10.0).round(2)}
    output_volumes = {"Ligation Product" => (REACTION_VOLUME*0.95 - 2.0).round}
    
    show do
        title "Keep all items on ice"
        warning "Note: All items used in this protocol should be kept on ice (or thawed at room temperature then immediately transfered to ice)."
    end
    
    operations.add_static_inputs "Ligase", "T4 HC DNA Ligase", "Enzyme Stock"
    operations.add_static_inputs "Buffer", "T4 DNA Ligase Buffer", "Enzyme Buffer Stock"
    check_user_inputs ["Insert", "Vector"], input_volumes, current_taken_items
    assign_input_items ["Ligase", "Buffer"], input_volumes, current_taken_items
    return {} if check_for_errors
    operations.sort_by! {|op| [op.input("Vector").item.id, op.input_array("Insert").items[0].id]}
    
    operations.each do |op|
        water_to_add = (REACTION_VOLUME - input_volumes["Insert"]*op.input_array("Insert").items.count - input_volumes["Vector"] - input_volumes["Ligase"] - input_volumes["Buffer"]).round(2)
        if water_to_add > 0.000001
            op.temporary[:water_to_add] = water_to_add
        else
            op.error :volume_error, "Water to add evaluated to negative value, possibly due to too many inputs."
        end
    end
    
    robust_make ["Ligation Product"], current_taken_items
    
    robust_take_inputs ["Insert", "Vector", "Buffer"], current_taken_items, interactive: true
    
    show do
        title "Add reagents to reaction tubes"
        note "Get out #{operations.running.count} new 1.5 ml tubes. Label and add reagents to tubes according to the following table."
        table operations.start_table
        .output_item("Ligation Product")
        .custom_column(heading: "Buffer to add", checkable: true) { |op| "#{input_volumes["Buffer"]} µl of #{op.input("Buffer").item.id} (#{op.input("Buffer").sample.name})"}
        .custom_column(heading: "Water to add", checkable: true) { |op| "#{op.temporary[:water_to_add]} µl of water"}
        .custom_column(heading: "Vector to add", checkable: true) { |op| "#{input_volumes["Vector"]} µl of #{op.input("Vector").item.id}"}
        .custom_column(heading: "Inserts to add", checkable: true) { |op| op.input_array("Insert").items.each_with_index.map {|insert, i| "#{input_volumes["Insert"]} µl of #{insert.id}"}.join(", ")}
        .end_table
    end
    
    robust_release_inputs ["Insert", "Vector", "Buffer"], current_taken_items, interactive: true
    
    robust_take_inputs ["Ligase"], current_taken_items, interactive: true
    
    show do
        title "Add #{operations.running[0].input("Ligase").sample.name} to reaction tubes"
        note "Add #{operations.running[0].input("Ligase").sample.name} to reaction tubes according to the following table"
        table operations.start_table
        .output_item("Ligation Product")
        .custom_column(heading: "Ligase", checkable: true) { |op| "#{input_volumes["Ligase"]} µl of #{op.input("Ligase").item.id} (#{op.input("Ligase").sample.name})"}
        .end_table
    end
    
    robust_release_inputs ["Ligase"], current_taken_items, interactive: true
    
    show do
      title "Centrifuge reactions"
      check "Briefly spin down reactions in the microcentrifuge by holding the \">>\" button for 3 seconds to collect liquid at the bottom of tubes"
      warning "Make sure to balance the centrifuge!"
    end
    
    # Display table to tech
    show do
        title "Allow reaction to occur on bench (room temperature)"
        note "Let reactions sit at the bench for 2 hours (at room temperature)"
        timer initial: { hours: 2, minutes: 0, seconds: 0}
        warning "After incubation, the ligation products should be used immediately. Do not store overnight."
    end
    
    store_outputs_with_volumes output_volumes, current_taken_items, interactive: true
    return {}
  end
end
