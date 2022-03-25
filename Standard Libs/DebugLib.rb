module Debug
  def print_object obj
    if [Numeric, String].any? { |c| obj.is_a? c }
      obj
    elsif [Array].any? { |c| obj.is_a? c }
      obj.map { |item| print_object item }
    elsif [Hash].any? { |c| obj.is_a? c }
      Hash[obj.map { |k, v| [k, print_object(v)] }]
    else
      s = obj ? obj.id.to_s : ""
      s += " #{obj.name}" if obj.class.method_defined? :name
      s
    end
  end
    
  def log_info *args
    if debug
      show do
        title "Debug slide (#{args.length} #{"arg".pluralize args.length})"
        
        args.each do |arg|
          note "#{arg.class}: #{print_object arg}"
        end
      end
    end
  end
end
