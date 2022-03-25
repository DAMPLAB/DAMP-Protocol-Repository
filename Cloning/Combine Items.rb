needs "Cloning Libs/Cloning"
needs "Standard Libs/Debug Lib"

class Protocol
    include Cloning
    include Debug
    def main
        current_taken_items = []
        input_volumes = {}
        output_volumes = {}
        check_user_inputs ["Items to Combine"], input_volumes, current_taken_items
        return {} if check_for_errors
        
        robust_take_inputs ["Items to Combine"], current_taken_items, interactive: true
        robust_make ["Combined Item"], current_taken_items
        table_matrix = Array.new() {Array.new()}
        table_matrix[0] = ["Items to Combine", "Output Item"]
        operations.running.each_with_index do |op, i|
            table_matrix[i+1] = [op.input_array("Items to Combine").items.to_sentence, {content: op.output("Combined Item").item.to_s, check: true}]
        end
        show do
            title "Combine items based on the following table"
            note "Create and label the following output items by combining input items (transfer full volumes of input items to output item containers)"
            table table_matrix
            check "Discard empty input items."
        end
        operations.each{|op| op.input_array("Items to Combine").items.each{|i| i.mark_as_deleted}}
        characterize operations.running.map{|op| op.output("Combined Item").item}, current_taken_items
        operations.running.store io:"output", interactive: true
        return {}
    end
end
