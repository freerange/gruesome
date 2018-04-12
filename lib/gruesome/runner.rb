require_relative './z/machine'
require_relative './z/memory'

module Gruesome

  class Runner

    def load_game_file(game_file)
      memory_size = File.size(game_file)
      file = File.new(game_file, "rb")
      Z::Memory.new(file.read(memory_size))
    end


    def restore_memory(game_file, memory)
      File.open(save_file_name(game_file), "rb") do |f|
        memory.restore(f)
      end
      memory
    end

    def save_memory(game_file, memory)
      File.open(save_file_name(game_file), "wb+") do |f|
        memory.save(f)
      end
    end

    def save_file_name(game_file)
      file = File.new(game_file)
      File.basename(file, File.extname(file)) + ".sav"
    end

    def run_game(game_file, &block)
      memory = load_game_file(game_file)
      output_stream = StringIO.new
      session_ended, memory = block.call(memory.dup, output_stream)
      unless session_ended
        save_memory(game_file, memory)
      end
      return [session_ended, output_stream.string]
    end

    def start(game_file)
      run_game(game_file) do |memory, output_stream|
        Z::Machine.new.start(memory, output_stream)
      end
    end

    def continue(game_file, command)
      run_game(game_file) do |memory, output_stream|
        memory = restore_memory(game_file, memory)
        Z::Machine.new.continue(memory, output_stream, command)
      end
    end

  end

end
