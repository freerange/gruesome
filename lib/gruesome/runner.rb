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
      session_ended, memory = block.call(memory.dup)
      unless session_ended
        save_memory(game_file, memory)
      end
    end

    def start(game_file)
      run_game(game_file) do |memory|
        Z::Machine.new.start(memory)
      end
    end

    def continue(game_file, command)
      run_game(game_file) do |memory|
        memory = restore_memory(game_file, memory)
        Z::Machine.new.continue(memory, command)
      end
    end

  end

end
