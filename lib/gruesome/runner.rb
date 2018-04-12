require_relative './z/machine'
require_relative './z/memory'

module Gruesome

  class LocalIO
    def initialize(game_file)
      @game_file = game_file
    end

    def load_game_file
      memory_size = File.size(@game_file)
      file = File.new(@game_file, "rb")
      Z::Memory.new(file.read(memory_size))
    end

    def restore_memory(memory)
      File.open(save_file_name, "rb") do |f|
        memory.restore(f)
      end
      memory
    end

    def save_memory(memory)
      File.open(save_file_name, "wb+") do |f|
        memory.save(f)
      end
    end

    def save_file_name
      file = File.new(@game_file)
      File.basename(file, File.extname(file)) + ".sav"
    end
  end

  class Runner
    def run_game(io, &block)
      memory = io.load_game_file
      output_stream = StringIO.new
      session_ended, memory = block.call(memory.dup, output_stream)
      unless session_ended
        io.save_memory(memory)
      end
      return [session_ended, output_stream.string]
    end

    def start(io)
      run_game(io) do |memory, output_stream|
        Z::Machine.new.start(memory, output_stream)
      end
    end

    def continue(io, command)
      run_game(io) do |memory, output_stream|
        memory = io.restore_memory(memory)
        Z::Machine.new.continue(memory, output_stream, command)
      end
    end

  end

end
