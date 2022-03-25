# Purify Gel Protocol
needs "Cloning Libs/Cloning"
needs "Standard Libs/Debug Lib"

# This protocol purfies gel slices into DNA fragment stocks.

class Protocol
  include Cloning
  include Debug
  
  DENSITY = 1.0 / 1000.0 #grams per microliter
  BUFFER_TO_GEL_RATIO = 3 #volumes of buffer per volume of gel
  ISOPROP_TO_GEL_RATIO = 1 #volumes of isopropanol per volume of gel (qiagen kit recommendation)
  MAX_COLUMN_VOLUME = 700.0 #microliters
  
  def main
    current_taken_items = []
    output_volumes = {"Fragment" => 27}
    operations.sort_by! {|op| op.input("Gel").item.id}
    
    # While testing, assign a random weight value
    operations.each{ |op| op.set_input_data("Gel", :weight, Random.rand / 10.0 + 0.1)  } if debug
    
    # Dissolved gel solution should be 1/5th isopropanol and the rest gel + QG. Always uses max amount of QG so that all tubes have same weight.
    operations.each do |op|
        current_volume = (op.input_data("Gel", :weight).to_f / DENSITY)
        op.temporary[:is_divided] = current_volume > MAX_COLUMN_VOLUME / (BUFFER_TO_GEL_RATIO + ISOPROP_TO_GEL_RATIO + 1)
        if op.temporary[:is_divided]
            op.temporary[:buffer_to_add]  = ((8.0 / 5.0) * MAX_COLUMN_VOLUME - current_volume).round(2)
            op.temporary[:isoprop_to_add]  = ((2.0 / 5.0) * MAX_COLUMN_VOLUME).round(2)
        else
            op.temporary[:buffer_to_add]  = ((4.0 / 5.0) * MAX_COLUMN_VOLUME - current_volume).round(2)
            op.temporary[:isoprop_to_add]  = ((1.0 / 5.0) * MAX_COLUMN_VOLUME).round(2)
        end
    end
    
    robust_make ["Fragment"], current_taken_items
    
    robust_take_inputs ["Gel"], current_taken_items, interactive: true
    
    show do
        title "Warm up water"
        check "Add #{(operations.running.count*output_volumes["Fragment"]*1.5).round(2)} µl of water to a tube. Label it \"Water\" and place on the 55C heat block."
    end
    
    show do
      title "Add QG buffer and isopropanol"
      note "This protocol uses the QIAquick Gel Extraction Kit"
      note "Add the following volumes of QG buffer and isopropanol to the corresponding tubes."
      table operations.start_table
      .input_item("Gel")
      .custom_column(heading: "QG Volume in µl", checkable: true) { |op| op.temporary[:buffer_to_add]}
      .custom_column(heading: "Isopropanol Volume in µl", checkable: true) { |op| op.temporary[:isoprop_to_add]}
      .end_table
    end
    
    show do
      title "Place all tubes in a 55 degree heat block"
      timer initial: { hours: 0, minutes: 10, seconds: 0}
      note "Vortex every few minutes to speed up the process."
      note "If the gel is not fully dissolved after 10 minutes, continue heating until fully dissolved."
    end
    
    tube_count = operations.count
    table_matrix = Array.new(tube_count + 1) {Array.new(2) {"Error"}}
    table_matrix[0] = ["1.5 ml tube (dissolved gel slice)", "Spin column number"]
    operations.each_with_index do |op, op_index|
        table_matrix[op_index+1] = [op.input("Gel").item.id.to_s, (op_index+1).to_s]
        op.temporary[:tube_number] = op_index+1
    end
    
    show do
        title "Transfer to spin columns and spin"
        check "Get out #{tube_count} new spin columns and collection tubes and label from 1 to #{tube_count}"
        check "Transfer 700 µl (no more) of liquid from the 1.5 ml tubes containing dissolved gel slices to the spin columns according to the following chart:"
        table table_matrix
        warning "Do not discard 1.5 ml tubes yet!" if operations.any? {|op| op.temporary[:is_divided]}
        centrifuge tube_count, 13000, 1
        check "Discard flow through."
    end
    
    tube_count = operations.select{|op| op.temporary[:is_divided]}.count
    table_matrix = Array.new(tube_count + 1) {Array.new(2) {"Error"}}
    table_matrix[0] = ["1.5 ml tube (dissolved gel slice)", "Spin column number"]
    operations.select{|op| op.temporary[:is_divided]}.each_with_index do |op, op_index|
        table_matrix[op_index+1] = [op.input("Gel").item.id.to_s, op.temporary[:tube_number].to_s]
    end
    
    show do
        title "Transfer additional liquid from 1.5 ml tubes to spin columns and spin"
        check "Transfer 700 µl of liquid from the 1.5 ml tubes containing dissolved gel slices to the spin columns according to the following chart:"
        table table_matrix
        check "Discard empty 1.5 ml tubes."
        centrifuge tube_count, 13000, 1
        check "Discard flow through."
    end if operations.any? {|op| op.temporary[:is_divided]}
    
    show do
      title "Add more QG Buffer"
      check "Add 500 µl QG buffer to columns."
      check "Spin at 13000 rpm for 1 min."
      check "Discard flow through."
    end
    
    show do
      title "Add PE Buffer"
      check "Add 400 µl PE buffer to columns."
      check "Let columns sit at room temperature for 5 minutes."
      timer initial: { hours: 0, minutes: 5, seconds: 0}
      check "Spin at 13000 rpm for 60 seconds."
      check "Discard flow through."
    end
    
    show do
      title "Add additional PE Buffer"
      check "Add 400 µl PE buffer to columns (repeat of last step)."
      check "Let columns sit at room temperature for 2 minutes."
      timer initial: { hours: 0, minutes: 2, seconds: 0}
      check "Spin at 13000 rpm for 60 seconds."
      check "Discard flow through."
      check "Spin at 13000 rpm for 5 minutes to remove residual PE buffer from columns."
    end
    
    table_matrix = Array.new(operations.count + 1) {Array.new(2) {"Error"}}
    table_matrix[0] = ["Spin column number", "Item ID to write on 1.5 mL tube"]
    operations.each_with_index do |op, op_index|
        table_matrix[op_index + 1][0] = (op_index + 1).to_s
        table_matrix[op_index + 1][1] = op.output("Fragment").item.id.to_s
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
        check "Pipette 30 µl from the tube of warm water on the 55C heat block into the CENTER of each column without touching the membrane"
        check "Let the columns sit for 4 minutes on the bench."
        centrifuge operations.count, 13000, 1
        check "Discard columns, but KEEP 1.5 ml tubes containing flowthrough!"
        check "Discard empty tube of warm water."
    end

    operations.each do |op|
      op.input("Gel").item.mark_as_deleted
      op.input("Gel").item.save
    end
    
    robust_release_inputs ["Gel"], current_taken_items, interactive: true
    
    store_outputs_with_volumes output_volumes, current_taken_items, interactive: true
    check_for_errors
    
    log_info "op id", operations[0].operation_type.id
    
    return {}
    
  end
  
end
