# Tailwind-friendly Haml class/id parsing. Stock Haml treats `[...]` after a
# partial class as object-ref syntax and splits `.max-w-[1.5rem]` on `.` inside
# brackets. Lux keeps bracket blocks inside a class token and only treats `#` as
# an id delimiter when it is not immediately preceded by `[` or `-`.
module Haml
  class Parser
    class << self
      def parse_class_and_id(list)
        attributes = {}
        return attributes if list.empty?

        i = 0
        while i < list.length
          case list[i]
          when '.'
            i += 1
            start = i
            i = scan_class_segment(list, i)
            append_class!(attributes, list[start...i]) if i > start
          when '#'
            break unless id_delimiter?(list, i)

            i += 1
            start = i
            i = scan_id_segment(list, i)
            attributes[ID_KEY] = list[start...i] if i > start
          else
            break
          end
        end

        attributes
      end

      def consume_class_and_id(list)
        i = 0
        while i < list.length
          case list[i]
          when '.'
            i += 1
            i = scan_class_segment(list, i)
          when '#'
            break unless id_delimiter?(list, i)

            i += 1
            i = scan_id_segment(list, i)
          else
            break
          end
        end
        i
      end

      def id_delimiter?(list, i)
        prev = i.positive? ? list[i - 1] : nil
        prev != '[' && prev != '-'
      end

      # IDs stop at whitespace and attribute/action delimiters so inline text
      # after e.g. `%span#nfc-node hello...` is not swallowed (trailing `.`
      # in that text would otherwise trip the illegal_element check).
      def scan_id_segment(list, i)
        while i < list.length
          case list[i]
          when '.', /\s/, '{', '(', '[', '=', ?~, ?&, ?<, ?>, '!'
            break
          when '/'
            break if slash_ends_class?(list, i)
          else
            i += 1
          end
        end
        i
      end

      def scan_class_segment(list, i)
        while i < list.length
          case list[i]
          when '['
            i += 1
            depth = 1
            while i < list.length && depth.positive?
              depth += 1 if list[i] == '['
              depth -= 1 if list[i] == ']'
              i += 1
            end
          when '#'
            break if id_delimiter?(list, i)

            i += 1
          when '.'
            break
          when '=', ?~, ?&, ?<, ?>
            break
          when '!'
            break if i.positive? && segment_started?(list, i)
          when '/'
            break if slash_ends_class?(list, i)
          when /\s/, ?{, ?(, ?[
            break
          else
            i += 1
          end
        end
        i
      end

      def segment_started?(list, i)
        prev = list[i - 1]
        prev != '.' && prev != '#'
      end

      def slash_ends_class?(list, i)
        nxt = list[i + 1]
        nxt.nil? || nxt =~ /\s/ || nxt == '=' || nxt == '~' || nxt == '&'
      end

      def append_class!(attributes, segment)
        if attributes[CLASS_KEY]
          attributes[CLASS_KEY] += ' '
        else
          attributes[CLASS_KEY] = ''
        end
        attributes[CLASS_KEY] += segment
      end
    end

    def parse_tag(text)
      match = text.match(/\A%([-:\w]+)(.*)\z/m)
      raise SyntaxError.new(Error.message(:invalid_tag, text)) unless match

      tag_name  = match[1]
      remainder = match[2] || ''
      attr_end  = self.class.consume_class_and_id(remainder)
      attributes = remainder[0...attr_end]
      rest       = remainder[attr_end..-1] || ''

      if !attributes.empty? && /[.#](\.|#|\z)/.match?(attributes)
        raise SyntaxError.new(Error.message(:illegal_element))
      end

      new_attributes_hash = old_attributes_hash = last_line = nil
      object_ref = :nil
      attributes_hashes = {}
      while rest && !rest.empty?
        case rest[0]
        when ?{
          break if old_attributes_hash
          old_attributes_hash, rest, last_line = parse_old_attributes(rest)
          attributes_hashes[:old] = old_attributes_hash
        when ?(
          break if new_attributes_hash
          new_attributes_hash, rest, last_line = parse_new_attributes(rest)
          attributes_hashes[:new] = new_attributes_hash
        when ?[
          break unless object_ref == :nil
          object_ref, rest = balance(rest, ?[, ?])
        else break
        end
      end

      if rest && !rest.empty?
        nuke_whitespace, action, value = rest.scan(/(<>|><|[><])?([=\/\~&!])?(.*)?/)[0]
        if nuke_whitespace
          nuke_outer_whitespace = nuke_whitespace.include? '>'
          nuke_inner_whitespace = nuke_whitespace.include? '<'
        end
      end

      if @options.remove_whitespace
        nuke_outer_whitespace = true
        nuke_inner_whitespace = true
      end

      value = value.nil? ? '' : value.strip!

      [tag_name, attributes, attributes_hashes, object_ref, nuke_outer_whitespace,
       nuke_inner_whitespace, action, value, last_line || @line.index + 1]
    end
  end
end
