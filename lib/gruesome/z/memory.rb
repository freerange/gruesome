require_relative 'header'

# The Z-Machine Memory is a simple array of bytes
#
# There are three regions: Dynamic, Static, and High
#
# Dynamic Memory can be read and written to by a program
# Static Memory can only be read
# High Memory cannot be accessed by load/store instructions
#
# High Memory can overlap Static, but never Dynamic
#
# Memory is stored in big endian

# Also included as memory space, yet separated from the
# RAM itself: the stack, program counter, and a routine
# call stack which holds the stacks of the currently
# invocated routines

# The stack is weird. Every function call starts with an empty stack
# and any work left in the stack upon a return is lost. So there are
# actually many stacks... one stack to hold the stacks in play, and
# a stack for each active function.
#
# The stack holds the return address and the (up to) 15 local variables
# for the routine as accessed by variables %01 to %0f.
#
# Variable %00 is the top of the stack, writing to it pushes, reading
# from it pulls.
#
# Illegal access to variables will halt the machine. Such as illegally
# accessing local variables that do not exist as the routine header
# will specify an exact number.

module Gruesome
  module Z

    # This class holds the memory for the virtual machine
    class Memory
      attr_accessor :program_counter
      attr_reader :num_locals
      attr_reader :num_arguments

      def initialize(contents, save_file_name)
        @call_stack = []
        @save_file_name = save_file_name
        @stack = []
        @memory = contents
        @num_locals = 0
        @num_arguments = 0

        # Get the header information
        @header = Header.new(@memory)
        @program_counter = @header.entry

        # With the header info, discover the bounds of each memory region
        @dyn_base = 0x0
        @dyn_limit = @header.static_mem_base

        # Cannot Write to Static Memory
        @static_base = @header.static_mem_base
        @static_limit = @memory.length

        # Cannot Access High Memory
        @high_base = @header.high_mem_base
        @high_limit = @memory.length

        # Error if high memory overlaps dynamic memory
        if @high_base < @dyn_limit
          # XXX: ERROR
        end

        # Check machine endianess
        @endian = [1].pack('S')[0] == 1 ? 'little' : 'big'
      end

      def packed_address_to_byte_address(address)
        if @header.version <=3
          address * 2
        elsif @header.version <= 5
          address * 4
        end
      end

      # Sets up the environment for a new routine
      def push_routine(return_addr, num_locals, num_arguments, destination)
        # pushes the stack onto the call stack
        @call_stack.push @num_locals
        @call_stack.push @num_arguments
        @call_stack.push destination
        @call_stack.push @stack

        # empties the current stack
        @stack = Array.new()

        # pushes the return address onto the stack
        @stack.push(return_addr)

        # push locals
        num_locals.times do
          @stack.push 0
        end

        @num_locals = num_locals
        @num_arguments = num_arguments
      end

      # Tears down the environment for the current routine
      def pop_routine()
        # return the return address
        return_addr = @stack[0]
        @stack = @call_stack.pop
        destination = @call_stack.pop
        @num_arguments = @call_stack.pop
        @num_locals = @call_stack.pop

        {:destination => destination, :return_address => return_addr}
      end

      def readb(address)
        if address < @high_base
          force_readb(address)
        else
          # XXX: Access violation
          raise "Access Violation accessing $" + sprintf("%04x", address)
          nil
        end
      end

      def readw(address)
        if (address + 1) < @high_base
          force_readw(address)
        else
          # XXX: Access violation
          raise "Access Violation accessing $" + sprintf("%04x", address)
          nil
        end
      end

      def writeb(address, value)
        if address < @static_base
          force_writeb(address, value)
        else
          # XXX: Access violation
          raise "Access Violation (W) accessing $" + sprintf("%04x", address)
          nil
        end
      end

      def writew(address, value)
        if (address + 1) < @static_base
          force_writew(address, value)
        else
          # XXX: Access violation
          raise "Access Violation (W) accessing $" + sprintf("%04x", address)
          nil
        end
      end

      def force_readb(address)
        if address < @memory.size
          @memory.getbyte(address)
        else
          # XXX: Access Violation
          raise "Major Access Violation accessing $" + sprintf("%04x", address)
          nil
        end
      end

      def force_readw(address)
        if (address + 1) < @memory.size
          if @endian == 'little'
            (@memory.getbyte(address+1) << 8) | @memory.getbyte(address)
          else
            (@memory.getbyte(address) << 8) | @memory.getbyte(address+1)
          end
        else
          # XXX: Access Violation
          raise "Major Access Violation accessing $" + sprintf("%04x", address)
          nil
        end
      end

      def force_writeb(address, value)
        if address < @memory.size
          @memory.setbyte(address, (value & 255))
        else
          # XXX: Access Violation
          raise "Major Access (W) Violation accessing $" + sprintf("%04x", address)
          nil
        end
      end

      def force_writew(address, value)
        if (address + 1) < @memory.size
          low_byte = value & 255
          high_byte = (value >> 8) & 255

          if @endian == 'little'
            tmp = high_byte
            high_byte = low_byte
            low_byte = tmp
          end

          @memory.setbyte(address, high_byte)
          @memory.setbyte(address+1, low_byte)
        else
          # XXX: Access Violation
          raise "Major Access (W) Violation accessing $" + sprintf("%04x", address)
          nil
        end
      end

      def contents
        @memory
      end

      # Read from variable number index
      def readv(index)
        if index == 0
          # pop from stack
          @stack.pop
        elsif index >= 16
          index -= 16
          readw(@header.global_var_addr + (index*2))
        elsif index <= @num_locals
          @stack[index]
        else
          raise "Variable Access Violation. No such variable %#{index}."
          # XXX: Error
        end
      end

      # Write value to variable number index
      def writev(index, value)
        value &= 65535
        if index == 0
          # push to stack
          @stack.push value
        elsif index >= 16
          index -= 16
          writew(@header.global_var_addr + (index*2), value)
        elsif index <= @num_locals
          @stack[index] = value
        else
          # XXX: Error
        end
      end

      def force_readzstr(index, max_len = -1)
        chrs = []
        continue = true
        orig_index = index

        until continue == false do
          if max_len != -1 and (index + 2 - orig_index) > max_len
            break
          end

          byte1 = force_readb(index)
          byte2 = force_readb(index+1)

          index += 2

          chrs << ((byte1 >> 2) & 0b11111)
          chrs << (((byte1 & 0b11) << 3) | (byte2 >> 5))
          chrs << (byte2 & 0b11111)

          continue = (byte1 & 0b10000000) == 0
        end

        return [index - orig_index, chrs]
      end

      def save
        # Save contents of dynamic memory to disk
        File.open(@save_file_name, "wb+") do |f|
          f.puts @program_counter
          f.puts (@call_stack.size / 4)
          @call_stack.each_with_index do |call_stack, i|
            if (i % 4) != 3
              f.puts call_stack
            else
              # this is stack
              stack = call_stack
              f.puts stack.size
              stack.each do |stack_entry|
                f.puts stack_entry
              end
            end
          end
          f.puts @num_locals
          f.puts @stack.size
          @stack.each do |stack_entry|
            f.puts stack_entry
          end

          @dyn_limit.times do |i|
            f.write force_readb(i).chr
          end
        end
      end

      def restore
        # Restore, if it can, the contents of memory from disk
        File.open(@save_file_name, "rb") do |f|
          @call_stack = []

          @program_counter = f.readline.to_i
          call_stack_size = f.readline.to_i

          call_stack_size.times do
            num_locals = f.readline.to_i
            num_args = f.readline.to_i
            destination = f.readline.to_i
            stack_size = f.readline.to_i

            stack = []
            stack_size.times do |i|
              stack.push f.readline.to_i
            end

            @call_stack.push num_locals
            @call_stack.push num_args
            @call_stack.push destination
            @call_stack.push stack
          end
          @num_locals = f.readline.to_i
          stack_size = f.readline.to_i

          @stack = []
          stack_size.times do |i|
            @stack.push f.readline.to_i
          end

          i = 0
          f.read.each_byte do |b|
            force_writeb(i, b)
            i += 1
          end
        end
      end
    end
  end
end
