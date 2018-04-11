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

      # Will create a new virtual machine for the game file
      def initialize(game_file)
        file = File.open(game_file, "rb")

        # I. Create memory space

        memory_size = File.size(game_file)
        save_file_name = File.basename(file, File.extname(file)) + ".sav"
        @memory = Memory.new(file.read(memory_size), save_file_name)

        # Set flags
        flags = @memory.force_readb(0x01)
        flags &= ~(0b1110000)
        @memory.force_writeb(0x01, flags)

        # Set flags 2
        flags = @memory.force_readb(0x10)
        flags &= ~(0b11111100)
        @memory.force_writeb(0x10, flags)

        # II. Read header (at address 0x0000) and associated tables
        @header = Header.new(@memory.contents)
        @object_table = ObjectTable.new(@memory)

        # III. Instantiate CPU
        @decoder = Decoder.new(@memory)
      end

      def run_instruction(processor, instruction)
        @memory.program_counter += instruction.length

        processor.execute(instruction)

      rescue RuntimeError => fuh
        raise "error at $" + sprintf("%04x", @memory.program_counter) + ": " + instruction.to_s(@header.version)
      end

      def is_read?(instruction)
        instruction.opcode == Opcode::SREAD || instruction.opcode == Opcode::READ_CHAR
      end

      def is_quit?(instruction)
        instruction.opcode == Opcode::QUIT
      end

      def restore_and_read_input(processor)
        @memory.restore
        instruction = @decoder.fetch
        if is_read?(instruction)
          run_instruction(processor, instruction)
        else
          raise "Expected game to have halted waiting for user input"
        end
      end

      def start
        processor = Processor.new(@memory)
        run_until_halted(processor)
      end

      def continue(command)
        input_stream = StringIO.new(command+"\n")
        processor = Processor.new(@memory, input_stream)
        restore_and_read_input(processor)
        run_until_halted(processor)
      end

      def run_until_halted(processor)

        next_instruction = @decoder.fetch

        until is_read?(next_instruction) || is_quit?(next_instruction)
          run_instruction(processor, next_instruction)
          next_instruction = @decoder.fetch
        end

        if is_read?(next_instruction)
          @memory.save
        end

      end
    end
  end
end
