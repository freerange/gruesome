# The Z-Machine processor unit will execute a stream of Instructions

require_relative 'instruction'
require_relative 'opcode'
require_relative 'header'
require_relative 'zscii'
require_relative 'abbreviation_table'
require_relative 'dictionary'
require_relative 'object_table'

module Gruesome
  module Z
    class Processor
      def initialize(memory, output_stream = $stdout, input_stream = $stdin)
        @memory = memory
        @header = Header.new(@memory.contents)
        @abbreviation_table = AbbreviationTable.new(@memory)
        @object_table = ObjectTable.new(@memory)
        @dictionary = Dictionary.new(@memory)
        @input_stream = input_stream
        @output_stream = output_stream
      end

      def routine_call(address, arguments, result_variable = nil)
        if address == 0
          # special case, do not call, simply return false
          if result_variable != nil
            @memory.writev(result_variable, 0)
          end
        else
          return_addr = @memory.program_counter
          @memory.program_counter = address

          # read routine
          num_locals = @memory.force_readb(@memory.program_counter)
          num_arguments = arguments.count
          @memory.program_counter += 1

          # create environment
          @memory.push_routine(return_addr, num_locals, num_arguments, result_variable)

          if @header.version <= 4
            # read initial values when version 1-4
            (1..num_locals).each do |i|
              @memory.writev(i, @memory.force_readw(@memory.program_counter))
              @memory.program_counter += 2
            end
          else
            # reset local vars to 0
            (1..num_locals).each do |i|
              @memory.writev(i, 0)
            end
          end

          # copy arguments over into locals
          idx = 1
          arguments.each do |i|
            @memory.writev(idx, i)
            idx += 1
          end
        end
      end

      def routine_return(result)
        frame = @memory.pop_routine

        if frame[:destination] != nil
          @memory.writev(frame[:destination], result)
        end
        @memory.program_counter = frame[:return_address]
      end

      def branch(branch_to, branch_on, result)
        if (result == branch_on)
          if branch_to == 0
            routine_return(0)
          elsif branch_to == 1
            routine_return(1)
          else
            @memory.program_counter = branch_to
#            @memory.program_counter -= 2
          end
        end
      end

      def execute(instruction)
        # Pull values from the variables if needed by the instruction
        # there are some exceptions for variable-by-reference instructions
        operands = instruction.operands.each_with_index.map do |operand, idx|
          if idx == 0 and Opcode.is_variable_by_reference?(instruction.opcode, @header.version)
            operand
          elsif instruction.types[idx] == OperandType::VARIABLE
            @memory.readv(operand)
          else
            operand
          end
        end

        case instruction.opcode
        when Opcode::ART_SHIFT
          places = unsigned_to_signed(operands[1])
          if places < 0
            @memory.writev(instruction.destination, unsigned_to_signed(operands[0]) >> places.abs)
          else
            @memory.writev(instruction.destination, operands[0] << places)
          end
        when Opcode::CALL, Opcode::CALL_1N, Opcode::CALL_VS, Opcode::CALL_VN, Opcode::CALL_VN2,
             Opcode::CALL_2S, Opcode::CALL_1S, Opcode::CALL_2N
          routine_call(@memory.packed_address_to_byte_address(operands[0]), operands[1..-1], instruction.destination)
        when Opcode::CHECK_ARG_COUNT
          result = @memory.num_arguments == operands[0]
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::CLEAR_ATTR
          @object_table.object_clear_attribute(operands[0], operands[1])
        when Opcode::DEC
          @memory.writev(operands[0], unsigned_to_signed(@memory.readv(operands[0])) - 1)
        when Opcode::INC
          @memory.writev(operands[0], unsigned_to_signed(@memory.readv(operands[0])) + 1)
        when Opcode::INC_CHK
          new_value = unsigned_to_signed(@memory.readv(operands[0])) + 1
          @memory.writev(operands[0], new_value)
          result = new_value > unsigned_to_signed(operands[1])
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::DEC_CHK
          new_value = unsigned_to_signed(@memory.readv(operands[0])) - 1
          @memory.writev(operands[0], new_value)
          result = new_value < unsigned_to_signed(operands[1])
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::INSERT_OBJ
          @object_table.object_insert_object(operands[1], operands[0])
        when Opcode::GET_CHILD
          child = @object_table.object_get_child(operands[0])
          @memory.writev(instruction.destination, child)
          result = child != 0
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::GET_NEXT_PROP
          next_prop = @object_table.object_get_next_property(operands[0], operands[1])
          @memory.writev(instruction.destination, next_prop)
        when Opcode::GET_PARENT
          parent = @object_table.object_get_parent(operands[0])
          @memory.writev(instruction.destination, parent)
        when Opcode::GET_PROP
          prop = @object_table.object_get_property_word(operands[0], operands[1])
          @memory.writev(instruction.destination, prop)
        when Opcode::GET_PROP_ADDR
          prop = @object_table.object_get_property_addr(operands[0], operands[1])
          @memory.writev(instruction.destination, prop)
        when Opcode::GET_PROP_LEN
          if operands[0] == 0
            result = 0
          else
            result = @object_table.object_get_property_data_size_from_address(operands[0])
          end
          @memory.writev(instruction.destination, result)
        when Opcode::GET_SIBLING
          sibling = @object_table.object_get_sibling(operands[0])
          @memory.writev(instruction.destination, sibling)
          result = sibling != 0
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::JUMP, Opcode::PIRACY
          @memory.program_counter += unsigned_to_signed(operands[0])
          @memory.program_counter -= 2
        when Opcode::JE
          result = operands[1..-1].inject(false) { |result, element|
            result | (operands[0] == element)
          }
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::JG
          result = operands[1..-1].inject(false) { |result, element|
            result | (unsigned_to_signed(operands[0]) > unsigned_to_signed(element))
          }
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::JIN
          result = @object_table.object_get_parent(operands[0]) == operands[1]
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::JL
          result = operands[1..-1].inject(false) { |result, element|
            result | (unsigned_to_signed(operands[0]) < unsigned_to_signed(element))
          }
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::JZ
          result = operands[0] == 0
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::LOAD
          if operands[0] != instruction.destination
            @memory.writev(instruction.destination, @memory.readv(operands[0]))

            # make sure to re-push the value since LOAD does not
            # change the stack but uses the value directly
            if operands[0] == 0
              @memory.writev(0, @memory.readv(instruction.destination))
            end
          end
        when Opcode::LOADB
          @memory.writev(instruction.destination, @memory.readb(operands[0] + unsigned_to_signed(operands[1])))
        when Opcode::LOADW
          @memory.writev(instruction.destination, @memory.readw(operands[0] + unsigned_to_signed(operands[1])*2))
        when Opcode::LOG_SHIFT
          places = unsigned_to_signed(operands[1])
          if places < 0
            @memory.writev(instruction.destination, operands[0] >> places.abs)
          else
            @memory.writev(instruction.destination, operands[0] << places)
          end
        when Opcode::NOP
        when Opcode::NEW_LINE
          @output_stream.puts
        when Opcode::POP
          # get rid of the first item on stack
          @memory.readv(0)
        when Opcode::PRINT
          @output_stream.print operands[0]
        when Opcode::PRINT_ADDR
          @output_stream.print ZSCII.translate(0, @header.version, @memory.force_readzstr(operands[0])[1], @abbreviation_table)
        when Opcode::PRINT_CHAR
          @output_stream.print ZSCII.translate_Zchar(operands[0])
        when Opcode::PRINT_NUM
          @output_stream.print unsigned_to_signed(operands[0]).to_s
        when Opcode::PRINT_OBJ
          @output_stream.print @object_table.object_short_text(operands[0])
        when Opcode::PRINT_PADDR
          str_addr = @memory.packed_address_to_byte_address(operands[0])
          @output_stream.print ZSCII.translate(0, @header.version, @memory.force_readzstr(str_addr)[1], @abbreviation_table)
        when Opcode::PRINT_RET
          @output_stream.puts operands[0]
          routine_return(1)
        when Opcode::PULL
          if @header.version == 6
            # TODO: Version 6 PULL instruction
            #
            # stack to pull from is given as operand[0]
            # instruction.destination is the destination resister
          else
            # pop value from stack
            @memory.writev(operands[0], @memory.readv(0))
          end
        when Opcode::PUSH
          # add value to stack
          @memory.writev(0, operands[0])
        when Opcode::PUT_PROP
          object_id = operands[0]
          prop_id = operands[1]
          prop_value = operands[2]

          @object_table.object_set_property_word(object_id, prop_id, prop_value)
        when Opcode::RANDOM
          value = unsigned_to_signed(operands[0])
          if value < 0
            # seed with value
            srand(value)
            result = 0
          elsif value == 0
            # seed with timestamp
            srand()
            result = 0
          else
            # pull random number from between 1 and value
            result = rand(value-1) + 1
          end
          @memory.writev(instruction.destination, result.to_i)
        when Opcode::READ_CHAR
          time = operands[2].to_f / 10.0
          routine = operands[3]

          char = @input_stream.getc
          @memory.writev(instruction.destination, ZSCII.translate_char_to_zchar(char, @header.version))
        when Opcode::REMOVE_OBJ
          @object_table.object_remove_object(operands[0])
        when Opcode::RESTORE
          if @header.version <= 4
            # @memory.restore
            if @header.version >= 4
              @memory.writev(instruction.destination, 1)
            end
            branch(instruction.branch_to, instruction.branch_on, true)
          end
        when Opcode::RET
          routine_return(operands[0])
        when Opcode::RET_POPPED
          routine_return(@memory.readv(0))
        when Opcode::RTRUE
          routine_return(1)
        when Opcode::RFALSE
          routine_return(0)
        when Opcode::SAVE
          if @header.version <= 4
            # @memory.save
            if @header.version >= 4
              @memory.writev(instruction.destination, 1)
            end
            branch(instruction.branch_to, instruction.branch_on, true)
          end
        when Opcode::SET_ATTR
          @object_table.object_set_attribute(operands[0], operands[1])
        when Opcode::SREAD

          # read the maximum number of bytes in the text-buffer
          max_bytes = @memory.force_readb(operands[0])

          # address of the next byte in the text-buffer
          addr = operands[0] + 1
          # read in a line of input from stdin
          line = @input_stream.readline.chomp('')

          # truncate line to fit the max characters given by text-buffer
          if line.length > max_bytes
            line = line[0..max_bytes]
          end

          # tokenize
          lexed = @dictionary.tokenize(line)

          # parse
          parsed = @dictionary.parse(lexed)

          # encode the line into a ZChar stream
          str = ZSCII.encode_to_zchars(line, @header.version)

          # write the text to the text-buffer
          num_bytes = 1
          first_position = 1
          if @header.version >= 5
            num_bytes += 1
            @memory.force_writeb(addr, line.length)
            first_position = 2
            addr += 1
          end

          str.each do |zchr|
            num_bytes += 1
            if num_bytes > max_bytes
              break
            end
            @memory.force_writeb(addr, zchr)
            addr += 1
          end

          if @header.version < 5
            # terminator
            if num_bytes <= max_bytes
              @memory.force_writeb(addr, 0)
            end
          end

          # write the parse-buffer
          max_bytes = @memory.force_readb(operands[1])
          max_bytes = 2 + max_bytes * 4
          addr = operands[1] + 1
          num_bytes = 1

          if num_bytes <= max_bytes
            @memory.force_writeb(addr, lexed.length)
            addr += 1
          end

          parsed.each do |token, index|
            num_bytes += 4
            if num_bytes > max_bytes
              break
            end
            @memory.force_writew(addr, token[:address])
            addr += 2
            @memory.force_writeb(addr, token[:size])
            addr += 1
            @memory.force_writeb(addr, token[:position]+first_position)
            addr += 1
          end
        when Opcode::TEST
          result = (operands[0] & operands[1]) == operands[1]
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::TEST_ATTR
          result = @object_table.object_has_attribute?(operands[0], operands[1])
          branch(instruction.branch_to, instruction.branch_on, result)
        when Opcode::ADD
          @memory.writev(instruction.destination,
            unsigned_to_signed(operands[0]) + unsigned_to_signed(operands[1]))
        when Opcode::SUB
          @memory.writev(instruction.destination,
            unsigned_to_signed(operands[0]) - unsigned_to_signed(operands[1]))
        when Opcode::MUL
          @memory.writev(instruction.destination,
            unsigned_to_signed(operands[0]) * unsigned_to_signed(operands[1]))
        when Opcode::DIV
          result = unsigned_to_signed(operands[0]).to_f / unsigned_to_signed(operands[1]).to_f
          if result < 0
            result = -(result.abs.floor)
          else
            result = result.floor
          end
          @memory.writev(instruction.destination, result.to_i)
        when Opcode::MOD
          a = unsigned_to_signed(operands[0])
          b = unsigned_to_signed(operands[1])
          result = a.abs % b.abs
          if a < 0
            result = -result
          end
          @memory.writev(instruction.destination, result.to_i)
        when Opcode::NOT
          @memory.writev(instruction.destination, ~(operands[0]))
        when Opcode::OR
          @memory.writev(instruction.destination, operands[0] | operands[1])
        when Opcode::AND
          @memory.writev(instruction.destination, operands[0] & operands[1])
        when Opcode::STORE
          if operands[0] == 0
            @memory.readv(operands[0])
          end
          @memory.writev(operands[0], operands[1])
        when Opcode::STOREB
          @memory.writeb(operands[0] + unsigned_to_signed(operands[1]), operands[2])
        when Opcode::STOREW
          @memory.writew(operands[0] + unsigned_to_signed(operands[1])*2, operands[2])
        else
          raise "opcode #{Opcode.name(instruction.opcode, @header.version)} not implemented"
        end
      end

      def unsigned_to_signed(op)
        sign = op & 0x8000
        if sign != 0
          -(65536 - op)
        else
          op
        end
      end
      private :unsigned_to_signed
    end
  end
end
