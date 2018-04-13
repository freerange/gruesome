require_relative './z/memory'
require_relative 'runner'
require 'base64'

module Gruesome
  class Stateless

    class StatelessIO

      attr_accessor :memory_bytes

      GAMES = {
        :zork => '../../test/zork1.z3'
      }

      def initialize(game, memory_bytes = nil)
        @game_path = File.join(File.dirname(__FILE__), GAMES[game])
        @memory_bytes = memory_bytes
      end

      def load_game_file
         memory_size = File.size(@game_path)
         file = File.new(@game_path, "rb")
         Z::Memory.new(file.read(memory_size))
      end

      def restore_memory(memory)
         memory.restore(StringIO.new(@memory_bytes))
         memory
      end

      def save_memory(memory)
         memory_io = StringIO.new
         memory.save(memory_io)
         @memory_bytes = memory_io.string
         memory
      end
    end

    def start(game)
       io = StatelessIO.new(game)
       ended, output = Runner.new.start(io)
       {
          :out => output,
          :base64memory => Base64.encode64(io.memory_bytes)
       }
    end

    def continue(game, command, memory)
      io = StatelessIO.new(game, Base64.decode64(memory))
      ended, output = Runner.new.continue(io, command)
      {
         :out => output,
         :base64memory => Base64.encode64(io.memory_bytes)
      }
    end

  end
end
