require 'optparse'

require_relative '../gruesome'
require_relative 'logo'
require_relative 'runner'
require_relative './z/dictionary'


module Gruesome
  class CLI
    BANNER = <<-USAGE
    Usage:
      gruesome play STORY_FILE

    Description:
      The 'play' command will start a session of the story given as STORY_FILE

    Example:
      gruesome play zork1.z3

    USAGE

    class << self
      def parse_options
        @opts = OptionParser.new do |opts|
          opts.banner = BANNER.gsub(/^    /, '')

          opts.separator ''
          opts.separator 'Options:'

          opts.on('-h', '--help', 'Display this help') do
            puts opts
            exit
          end
        end

        @opts.parse!
      end

      def CLI.run
        begin
          parse_options
        rescue OptionParser::InvalidOption => e
          warn e
          exit -1
        end

        def fail
          puts @opts
          exit -1
        end

        if ARGV.empty?
          fail
        end

        case ARGV.first
        when 'dict'
          game_file = ARGV[1]
          io = LocalIO.new(game_file)
          memory = io.load_game_file
          dictionary = Z::Dictionary.new(memory)
          i = 0
          while true do
            word =  dictionary.word(i)
            puts word
            i = i + 1
            if word.start_with? "zz"
              break
            end
          end
        when 'start'
          fail unless ARGV[1]
          game_file = ARGV[1]
          runner = Runner.new
          io = LocalIO.new(game_file)
          ended, output = runner.start(io)
          puts output
        when 'continue'
          fail unless ARGV[1] && ARGV[2]
          game_file = ARGV[1]
          command = ARGV[2]
          runner = Runner.new
          io = LocalIO.new(game_file)
          ended, output = runner.continue(io, command)
          puts output
        end
      end
    end
  end
end
