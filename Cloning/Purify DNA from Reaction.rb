# Purify Gel Protocol
needs "Standard Libs/Debug Lib"
needs "Cloning Libs/Cloning"

#Designed for QIAquick PCR purification kit

class Protocol
  include Debug
  include Cloning
  
  def main
    current_taken_items = []
    
    pcr_input_ops = operations.running.select{|op| op.input("Impure Reaction").object_type.name.include?("PCR")}
    input_volumes = {"DpnI" => (pcr_input_ops.count / operations.running.count.to_f).round(2) }
    output_volumes = {"Purified DNA" => 17}
    assign_input_items ["DpnI"], input_volumes, current_taken_items
    return {} if check_for_errors
    
    operations.each do |op|
        op.input("Impure Reaction").item.associate :volume, 50.0
    end if debug
    
    operations.add_static_inputs "DpnI", "DpnI", "Enzyme Stock"
    
    operations.sort_by! {|op| op.input("Impure Reaction").item.id}
    
    if pcr_input_ops.any?
        robust_take_inputs ["Impure Reaction", "DpnI"], current_taken_items, interactive: true
    
        show do
            title "Add DpnI to PCR input items"
            note "Add DpnI to PCR input items according to the following table:"
            table pcr_input_ops.start_table
            .input_item("Impure Reaction")
            .custom_column(heading: "DpnI to add") {|op| {content: "1 µl of #{op.input("DpnI").item}", check: true} }
            .end_table
        end
    
        pcr_input_ops.running.each do |op|
            op.input("Impure Reaction").item.move("37C incubator")
            op.input("Impure Reaction").item.save
        end
    
        robust_release_inputs ["Impure Reaction", "DpnI"], current_taken_items, interactive: true
    
        show do
            check "Wait 30 minutes before continuing"
            timer initial: { hours: 0, minutes: 30, seconds: 0}
        end
    end
    
    robust_take_inputs ["Impure Reaction"], current_taken_items, interactive: true
    
    robust_make ["Purified DNA"], current_taken_items
    
    table_matrix = Array.new(operations.count + 1) {Array.new(2)}
    table_matrix[0] = ["New 1.5 ml tube number", "Reaction item to add", "PX buffer to add"]
    operations.each_with_index do |op, op_index|
        table_matrix[op_index+1] = [(op_index+1).to_s, {content:"#{op.input("Impure Reaction").item.get(:volume)} µl of #{op.input("Impure Reaction").item.id}", check: true}, {content:"#{op.input("Impure Reaction").item.get(:volume) * 5} µl of PB buffer", check: true}]
    end
    
    show do
      title "Transfer to 1.5 mL tubes and add PB buffer"
      note "This protocol uses the QIAquick PCR Purification Kit."
      check "Get out #{operations.count} new 1.5 ml tubes and label them from 1 to #{operations.count}"
      check "Add inputs and PB buffer to new 1.5 ml tubes according to the following table:"
      table table_matrix
    end
        
    operations.each do |op|
      op.input("Impure Reaction").item.mark_as_deleted
      op.input("Impure Reaction").item.save
    end
    
    robust_release_inputs ["Impure Reaction"], current_taken_items, interactive: false
    
    show do
      title "Transfer to spin columns"
      check "Get out #{operations.count} spin columns and round bottom collection tubes. Place spin columns into collection tubes."
      check "Label both the spin columns with the numbers 1-#{operations.count}"
      check "Transfer contents of 1.5 ml tubes (500 µl) to spin columns with corresponding numbers."
      check "Discard the empty 1.5 ml tubes."
    end
    
    show do
      title "Centrifuge"
      centrifuge operations.running.count, 13000, 1
      check "Empty collection tubes by pouring waste liquid into miniprep waste container."
    end
    
    show do
      title "Add PE Buffer"
      check "Add 750 µl PE buffer to columns."
      check "Spin at 13000rpm for 60 seconds."
      check "Discard flow through into miniprep waste container."
      check "Spin at 13000rpm for 3 minutes to remove residual WS buffer from columns."
    end
    
    table_matrix = Array.new(operations.count + 1) {Array.new(2) {"Error"}}
    table_matrix[0] = ["Item ID to write on 1.5 mL tube", "Spin column number"]
    operations.each_with_index do |op, op_index|
        table_matrix[op_index + 1][0] = op.output("Purified DNA").item.id
        table_matrix[op_index + 1][1] = (op_index + 1).to_s
    end
    
    show do
        title "Transfer columns to fresh tubes"
        check "Get out #{operations.count} new 1.5 mL tubes."
        check "Label new tubes with the following item IDs, and transfer columns to these new tubes according to the following table:"
        table table_matrix
        check "Discard round bottom collection tubes."
    end
    
    show do
        title "Elute with water"
        check "Carefully pipette 20 µl of water onto the center of each column. Do not touch the column membrane with the pipette tip."
        check "Let the columns sit for 2 minutes on the bench."
        centrifuge operations.running.count, 13000, 1
        check "KEEP 1.5 ml tubes containing flowthrough!"
    end
    
    store_outputs_with_volumes output_volumes, current_taken_items, interactive: true
    check_for_errors
    
    log_info "op id", operations[0].operation_type.id
    
    return {}
    
  end
  
end

