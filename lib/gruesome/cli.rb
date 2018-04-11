require 'optparse'

require_relative '../gruesome'
require_relative 'logo'
require_relative './z/machine'

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
        when 'start'
          fail unless ARGV[1]
          game_file = ARGV[1]
          Z::Machine.new(game_file).start
        when 'continue'
          fail unless ARGV[1] && ARGV[2]
          game_file = ARGV[1]
          command = ARGV[2]
          Z::Machine.new(game_file).continue(command)
        end
      end
    end
  end
end
