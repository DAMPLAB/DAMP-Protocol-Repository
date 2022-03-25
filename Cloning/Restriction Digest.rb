needs "Cloning Libs/Cloning"
needs "Standard Libs/Debug Lib"

class Protocol
    
  include Debug
  include Cloning
  REACTION_VOLUME = 50.0
  
  def main
    current_taken_items = []
    # Remember to add volume information to input and output object types (and concentration data where applicable).
    input_volumes = {"Input DNA" => (0.38*REACTION_VOLUME).round(2), "Restriction Enzyme 1" => (0.03*REACTION_VOLUME).round(2), "Restriction Enzyme 2" => (0.03*REACTION_VOLUME).round(2), "Buffer" => (REACTION_VOLUME / 10.0).round(2)}
    output_volumes = {"Restriction Digest Product" => (REACTION_VOLUME*0.95 - 2.0).round}
    
    show do
        title "Keep all items on ice"
        warning "Note: All items used in this protocol should be kept on ice (or thawed at room temperature then immediately transfered to ice)."
    end
    
    operations.add_static_inputs "Buffer", "Cut Smart", "Enzyme Buffer Stock"
    check_user_inputs ["Input DNA"], input_volumes, current_taken_items
    assign_input_items ["Restriction Enzyme 1", "Restriction Enzyme 2", "Buffer"], input_volumes, current_taken_items
    return {} if check_for_errors
    operations.sort_by! {|op| op.input("Input DNA").item.id}
    
    operations.each do |op|
        water_to_add = (REACTION_VOLUME - input_volumes["Input DNA"] - input_volumes["Restriction Enzyme 1"] - input_volumes["Restriction Enzyme 2"] - input_volumes["Buffer"]).round(2)
        if water_to_add > 0.000001
            op.temporary[:water_to_add] = water_to_add
        else
            op.error :volume_error, "Water to add evaluated to negative value, possibly due to too many inputs."
        end
    end
    
    robust_make ["Restriction Digest Product"], current_taken_items
    
    robust_take_inputs ["Input DNA", "Buffer"], current_taken_items, interactive: true
    
    show do
        title "Add reagents to reaction tubes"
        note "Get out #{operations.running.count} new 1.5 ml tubes. Label and add reagents to tubes according to the following table."
        table operations.start_table
        .output_item("Restriction Digest Product")
        .custom_column(heading: "Buffer to add", checkable: true) { |op| "#{input_volumes["Buffer"]} µl of #{op.input("Buffer").item.id} (#{op.input("Buffer").sample.name})"}
        .custom_column(heading: "Water to add", checkable: true) { |op| "#{op.temporary[:water_to_add]} µl of water"}
        .custom_column(heading: "Input DNA", checkable: true) { |op| "#{input_volumes["Input DNA"]} µl of #{op.input("Input DNA").item.id}"}
        .end_table
    end
    
    robust_release_inputs ["Input DNA", "Buffer"], current_taken_items, interactive: true
    
    robust_take_inputs ["Restriction Enzyme 1", "Restriction Enzyme 2"], current_taken_items, interactive: true
    
    show do
        title "Add restriction enzymes to reaction tubes"
        note "Add restriction enzymes to reaction tubes according to the following table"
        table operations.start_table
        .output_item("Restriction Digest Product")
        .custom_column(heading: "Restriction Enzyme 1", checkable: true) { |op| "#{input_volumes["Restriction Enzyme 1"]} µl of #{op.input("Restriction Enzyme 1").item.id} (#{op.input("Restriction Enzyme 1").sample.name})"}
        .custom_column(heading: "Restriction Enzyme 2", checkable: true) { |op| "#{input_volumes["Restriction Enzyme 2"]} µl of #{op.input("Restriction Enzyme 2").item.id} (#{op.input("Restriction Enzyme 2").sample.name})"}
        .end_table
    end
    
    robust_release_inputs ["Restriction Enzyme 1", "Restriction Enzyme 2"], current_taken_items, interactive: true
    
    show do
      title "Centrifuge reactions"
      check "Briefly spin down reactions in the microcentrifuge by holding the \">>\" button for 3 seconds to collect liquid at the bottom of tubes"
      warning "Make sure to balance the centrifuge!"
    end
    
    # Display table to tech
    show do
        title "Incubate reactions in 37C incubator"
        note "Incubate reactions in 37C incubator"
        timer initial: { hours: 1, minutes: 0, seconds: 0}
        warning "After incubation, the products should be cleaned up immediately. Do not store more than 20 minutes."
    end
    
    store_outputs_with_volumes output_volumes, current_taken_items, interactive: true
    return {}
  end
end
