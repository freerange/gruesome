require_relative 'header'
require_relative 'memory'
require_relative 'decoder'
require_relative 'processor'
require_relative 'abbreviation_table'
require_relative 'object_table'

require 'stringio'

module Gruesome
  module Z

    # The class that initializes and maintains a Z-Machine
    class Machine

      def run_instruction(memory, processor, instruction)
        memory.program_counter += instruction.length
        processor.execute(instruction)
      rescue RuntimeError => fuh
        header = Header.new(memory.contents)
        raise "error at $" + sprintf("%04x", memory.program_counter) + ": " + instruction.to_s(header.version)
      end

      def is_read?(instruction)
        instruction.opcode == Opcode::SREAD || instruction.opcode == Opcode::READ_CHAR
      end

      def is_quit?(instruction)
        instruction.opcode == Opcode::QUIT
      end

      def set_flags(memory)
        flags = memory.force_readb(0x01)
        flags &= ~(0b1110000)
        memory.force_writeb(0x01, flags)

        flags = memory.force_readb(0x10)
        flags &= ~(0b11111100)
        memory.force_writeb(0x10, flags)
      end

      def start(memory)
        set_flags(memory)
        processor = Processor.new(memory)
        decoder = Decoder.new(memory)
        run_until_halted(memory, decoder, processor)
      end

      def continue(memory, command)
        set_flags(memory)
        processor = Processor.new(memory, StringIO.new(command+"\n"))
        decoder = Decoder.new(memory)

        instruction = decoder.fetch
        if is_read?(instruction)
          run_instruction(memory, processor, instruction)
        else
          raise "Expected game to have halted waiting for user input"
        end

        run_until_halted(memory, decoder, processor)
      end

      def run_until_halted(memory, decoder, processor)

        next_instruction = decoder.fetch

        until is_read?(next_instruction) || is_quit?(next_instruction)
          run_instruction(memory, processor, next_instruction)
          next_instruction = decoder.fetch
        end

        session_ended = is_quit?(next_instruction)
        return [session_ended, memory]
      end
    end
  end
end
