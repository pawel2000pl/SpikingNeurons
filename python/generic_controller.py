from math import ceil, log2
import numpy as np
#from bitarray import bitarray

clog2 = lambda x: ceil(log2(x))

class FrameGenerator:
    
    def __init__(self, ADDRESS_SIZE, WORD_SIZE):
        self.ADDRESS_SIZE = ADDRESS_SIZE
        self.WORD_SIZE = WORD_SIZE
        self.FRAME_BYTES = (self.ADDRESS_SIZE+self.WORD_SIZE+7)//8 + 2
        
                        
    def eat_frame(self, frame): # tuple of bytes (ints)
        x = 0
        for b in frame:
            x = x ^ b
        if frame[0] != 170 or x != 0 or len(frame) != self.FRAME_BYTES:
            raise Exception('Broken frame: '+str(frame))
        bits = sum(f << (8*i) for i, f in enumerate(frame))
        address = bits >> 8 & ((1 << self.ADDRESS_SIZE) - 1)
        value = (bits >> 8 >> self.ADDRESS_SIZE) & ((1 << self.WORD_SIZE) - 1)
        return (address, value)
    
    
    def build_frame(self, command, address, value): # command: 'r' / 'w'
        assert command in {'r', 'w'}
        assert address >= 0 and address < 2**self.ADDRESS_SIZE             
        assert value >= 0 and value < 2**self.WORD_SIZE    
        address = int(address)
        value = int(value)
        frame = [170 if command == 'w' else 85]
        bits = address | (value << self.ADDRESS_SIZE)
        for _ in range(self.FRAME_BYTES-2):
            frame.append(bits & 255)
            bits = bits >> 8
        x = 0
        for b in frame:
            x = x ^ b
        frame.append(x)
        return tuple(frame)
    
    
def frame2uart(frames, delay=8680, init_delay=1000000):
    code = []
    frame_len = len(frames)
    for fn, frame in enumerate(frames):
        code.append(f'$display("Frames: {fn} / {frame_len}");') 
        for byte in frame:        
            code.append(f'#{delay} tx <= 0;') 
            for bit in range(8):                
                code.append(f'#{delay} tx <= {(byte>>bit)&1};')
            code.append(f'#{delay} tx <= 1;')
            
    code.append(f'$display("Frames: {frame_len} / {frame_len}");') 
    return f"module transmitter(output logic tx);\ninitial\nbegin\ntx<=1;\n#{init_delay}\n" + "\n".join(code) + f"\n#{delay} tx<=1;\n#{init_delay} $finish;\nend\nendmodule"
    

class GenericController:
    
    def __init__(self, N=32, R=4, WORD_SIZE=32, RM=None):
        if RM is None:
            RM = clog2(N+1)+R
            
        self.RM = RM
        self.N = N
        self.R = R
        self.WORD_SIZE = WORD_SIZE
        self.LEARNING_BITS = 8
        
        self.WEIGHT_STATE_WORDS = (N*(N+3)*R+self.WORD_SIZE-1)//self.WORD_SIZE
        self.SWITCHES_WORDS = (3*N*N+self.WORD_SIZE-1)//self.WORD_SIZE
        self.MASK_WORDS = (N+self.WORD_SIZE-1)//self.WORD_SIZE        
        self.CORE_WORDS = self.WEIGHT_STATE_WORDS+self.SWITCHES_WORDS+self.MASK_WORDS
        
        self.CORE_ADDRESS_SIZE = clog2(self.CORE_WORDS)
        self.CORE_PADDED_ADDRESS = 1 << self.CORE_ADDRESS_SIZE
        self.ADDRESS_SIZE = 16
        
        self.CONFIG_ADDRESS_OFFSET = self.CORE_PADDED_ADDRESS+2*N
        self.BATCH_INPUT_ADDRESS_OFFSET = self.CONFIG_ADDRESS_OFFSET+32
        self.BATCH_OUTPUT_ADDRESS_OFFSET = self.BATCH_INPUT_ADDRESS_OFFSET+16384
        self.ADDRESS_SPACE = self.BATCH_OUTPUT_ADDRESS_OFFSET+2048
                        
        self.controller = FrameGenerator(self.ADDRESS_SIZE, self.WORD_SIZE)
        self.queue = []
        self.modified_addresses = set()
        
        self.mem_map = np.zeros(self.ADDRESS_SPACE*WORD_SIZE, dtype=np.byte)
        #self.mem_map = bitarray(self.CORE_WORDS*WORD_SIZE+2*N*WORD_SIZE, 'little')
          
        
    def create_network(self, input_size, *layers, zero=True, add_bias=True):
        assert sum(layers) <= self.N

        if zero:
            for i in range(self.N):
                for j in range(self.N):        
                    self.set_switch(i, j, 0)

                self.set_switch_output(i, 0)

        for i in range(layers[0]):
            for j in range(input_size):
                self.set_switch(i, j, 4)                
            if add_bias:
                self.set_switch(i, input_size%self.N, 1)

        integral = [0]
        for size in layers:
            integral.append(integral[-1] + size)
        integral = integral[1:]

        offset0 = 0
        for offset1, offset2 in zip(integral[:-1], integral[1:]):
            for i in range(offset1, offset2):
                for j in range(offset0, offset1):
                    self.set_switch(i, j, 2)
                if add_bias:
                    self.set_switch(i, offset1%self.N, 1)
            offset0 = offset1

        for i in range(integral[-2], integral[-1]):
            self.set_switch_output(i, 1)
            

    def eat_frame(self, frame, save=True):
        address, value = self.controller.eat_frame(frame)
        if save:
            self.set_mem(address*self.WORD_SIZE, self.WORD_SIZE, value, False)
        return address, value
        
        
    def queue_core(self, command='r'):        
        for address in range(self.CORE_WORDS):
            self.queue.append(self.controller.build_frame(command, address, self.get_mem(address*self.WORD_SIZE, self.WORD_SIZE)))
            
    
    def queue_inputs(self, command='w'):
        for address in range(self.CORE_PADDED_ADDRESS, self.CORE_PADDED_ADDRESS+self.N):
            self.queue.append(self.controller.build_frame(command, address, self.get_mem(address*self.WORD_SIZE, self.WORD_SIZE)))
            
    
    def queue_outputs(self, command='r'):
        for address in range(self.CORE_PADDED_ADDRESS+self.N, self.CORE_PADDED_ADDRESS+self.N*2):
            self.queue.append(self.controller.build_frame(command, address, self.get_mem(address*self.WORD_SIZE, self.WORD_SIZE)))

        
    def queue_config(self, command='r'):
        for address in range(self.CONFIG_ADDRESS_OFFSET, self.CONFIG_ADDRESS_OFFSET+9):
            self.queue.append(self.controller.build_frame(command, address, self.get_mem(address*self.WORD_SIZE, self.WORD_SIZE)))


    def load_memory(self):
        self.queue_core('r')
        self.queue_inputs('r')
        self.queue_outputs('r')
        

    def set_mem(self, bit_address, bit_length, value, set_as_modified=True):
        assert value >= 0 and value < 2**bit_length and bit_address >= 0 and bit_address+bit_length < self.ADDRESS_SPACE*self.WORD_SIZE and bit_length >= 0
        for i in range(bit_length):
            self.mem_map[bit_address+i] = (value >> i) & 1
        if set_as_modified:
            for i in range(ceil(bit_length/self.WORD_SIZE)):
                self.modified_addresses.add(bit_address//self.WORD_SIZE+i)
                
        
    def get_mem(self, bit_address, bit_length):
        return sum((1 << i) if b == 1 else 0 for i, b in enumerate(self.mem_map[bit_address:bit_address+bit_length]))

    
    def queue_changes(self, front=False):
        l = list()
        for change in self.modified_addresses:
            l.append(self.controller.build_frame('w', change, self.get_mem(change*self.WORD_SIZE, self.WORD_SIZE)))
        if front:
            self.queue = l + self.queue
        else:
            self.queue = self.queue + l
        self.modified_addresses = set()


    # i - neuron; j - weight
    def get_weight(self, i, j):
        return self.get_mem((i*(self.N+3)+j)*self.R, self.R)
    
    
    def set_weight(self, i, j, value):
        self.set_mem((i*(self.N+3)+j)*self.R, self.R, value)
        
        
    def get_switch(self, i, j):
        return self.get_mem(self.WEIGHT_STATE_WORDS*self.WORD_SIZE+3*(i*self.N+j), 3)
    
    
    def set_switch(self, i, j, value): # negation ^ (active loop | active input)
        self.set_mem(self.WEIGHT_STATE_WORDS*self.WORD_SIZE+3*(i*self.N+j), 3, value)
        
        
    def get_switch_output(self, i):
        return self.get_mem((self.WEIGHT_STATE_WORDS+self.SWITCHES_WORDS)*self.WORD_SIZE+i, 1)
    
    
    def set_switch_output(self, i, value):
        self.set_mem((self.WEIGHT_STATE_WORDS+self.SWITCHES_WORDS)*self.WORD_SIZE+i, 1, value)


    def get_input_value(self, i):
        return self.get_mem((self.CORE_PADDED_ADDRESS+i)*self.WORD_SIZE, self.WORD_SIZE)
    
    
    def set_input_value(self, i, value):
        self.set_mem((self.CORE_PADDED_ADDRESS+i)*self.WORD_SIZE, self.WORD_SIZE, value)
        
        
    def get_output_value(self, i):
        return self.get_mem((self.CORE_PADDED_ADDRESS+i+self.N)*self.WORD_SIZE, self.WORD_SIZE)
    
    
    def set_output_value(self, i, value):
        self.set_mem((self.CORE_PADDED_ADDRESS+i+self.N)*self.WORD_SIZE, self.WORD_SIZE, value)




    def get_output_counter(self):
        return self.get_mem((self.CONFIG_ADDRESS_OFFSET)*self.WORD_SIZE, self.WORD_SIZE)

    
    def set_output_counter(self, value):
        self.set_mem((self.CONFIG_ADDRESS_OFFSET)*self.WORD_SIZE, self.WORD_SIZE, value)
        

    def get_max_output_counter(self):
        return self.get_mem((self.CONFIG_ADDRESS_OFFSET+1)*self.WORD_SIZE, self.WORD_SIZE)

    
    def set_max_output_counter(self, value):
        self.set_mem((self.CONFIG_ADDRESS_OFFSET+1)*self.WORD_SIZE, self.WORD_SIZE, value)


    def get_entity_loss(self):
        return self.get_mem((self.CONFIG_ADDRESS_OFFSET+2)*self.WORD_SIZE, self.WORD_SIZE)
    

    def get_learning_actived(self):
        return self.get_mem((self.CONFIG_ADDRESS_OFFSET+3)*self.WORD_SIZE, self.WORD_SIZE)

    
    def set_learning_actived(self, value): 
        self.set_mem((self.CONFIG_ADDRESS_OFFSET+3)*self.WORD_SIZE, self.WORD_SIZE, value)


    def get_learning_mode(self):
        return self.get_mem((self.CONFIG_ADDRESS_OFFSET+4)*self.WORD_SIZE, self.WORD_SIZE)

    
    def set_learning_mode(self, value):  # 0 - with teacher, 1 - without teacher
        self.set_mem((self.CONFIG_ADDRESS_OFFSET+4)*self.WORD_SIZE, self.WORD_SIZE, value)


    def get_batch_buffer_size(self):
        return self.get_mem((self.CONFIG_ADDRESS_OFFSET+5)*self.WORD_SIZE, self.WORD_SIZE)

    
    def set_batch_buffer_size(self, value):  
        self.set_mem((self.CONFIG_ADDRESS_OFFSET+5)*self.WORD_SIZE, self.WORD_SIZE, value)
        

    def get_batch_loss(self):
        return self.get_mem((self.CONFIG_ADDRESS_OFFSET+6)*self.WORD_SIZE, self.WORD_SIZE)

    
    def set_batch_loss(self, value):  
        self.set_mem((self.CONFIG_ADDRESS_OFFSET+6)*self.WORD_SIZE, self.WORD_SIZE, value)
        
        
    def get_modify_probability(self):
        return self.get_mem((self.CONFIG_ADDRESS_OFFSET+7)*self.WORD_SIZE, self.WORD_SIZE)

    
    def set_modify_probability(self, value):  
        self.set_mem((self.CONFIG_ADDRESS_OFFSET+7)*self.WORD_SIZE, self.WORD_SIZE, value)
        
        
    def get_learning_one(self):
        return self.get_mem((self.CONFIG_ADDRESS_OFFSET+8)*self.WORD_SIZE, self.LEARNING_BITS)

    
    def set_learning_one(self, value):  
        self.set_mem((self.CONFIG_ADDRESS_OFFSET+8)*self.WORD_SIZE, self.LEARNING_BITS, value)
        
        
        
    def set_batch_entity(self, i, input_value, output_value=[0]): # arrays of ints; inputs: 0-255, outputs: 0-1
        assert len(input_value) <= self.N and len(output_value) <= self.N        
        input_value = input_value + [0] * (self.N - len(input_value))
        output_value = [0] * (self.N - len(output_value)) + output_value
        for j, (vi, vo) in enumerate(zip(input_value, output_value)):
            self.set_mem((self.BATCH_INPUT_ADDRESS_OFFSET*self.WORD_SIZE)+(i*self.N+j)*self.LEARNING_BITS, self.LEARNING_BITS, vi)
            self.set_mem(self.BATCH_OUTPUT_ADDRESS_OFFSET*self.WORD_SIZE+i*self.N+j, 1, vo)
        
        
        
    def clear_queue(self):
        self.queue = []
        
    
        
if __name__ == "__main__":    
    fg = FrameGenerator(8, 8)
    print(fg.eat_frame((170, 224, 31, 85)))
    print(fg.build_frame('w', 224, 31))
    
    gc = GenericController()
    #gc.load_memory()
    #print(len(gc.queue))
    
    #gc.set_mem(10, 10, 155, False)
    #print(gc.get_mem(9, 10))
    #print(gc.get_mem(10, 10))
    #print(gc.get_mem(11, 10))
        
    gc.set_weight(0, 5, 15)
    gc.set_weight(1, 5, 15)
    gc.set_weight(31, 31, 7)
    
    gc.load_memory()
    #gc.queue_outputs('r')
    gc.queue_changes(True)   
    for f in gc.queue[:5]:
        print(f)
        
    with open('commands.v', 'w') as f:
        f.write(frame2uart(gc.queue))
    
