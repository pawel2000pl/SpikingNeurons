from serial import Serial
from time import sleep
from generic_controller import GenericController


class UartController(GenericController):
    
    def __init__(self, device='/dev/ttyUSB0', baud=115200, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.device = device
        self.baud = baud
        self.serial = Serial(device, baud, timeout=0.005)
        
        
    def __del__(self):
        self.serial.close()
        
        
    def flush_queue(self):
        TRIALS = 16
        for frame in self.queue:
            for i in range(TRIALS):
                self.serial.write(bytes(frame))  
                self.serial.flush()
                if self.read_one(save=frame[0]==85) is not None:
                    break
                if i==TRIALS-1:
                    print("Cannot transmit frame:", frame, '[no response]')
            
        self.clear_queue()
        
        
    def flush(self):
        self.queue_changes(True)        
        self.flush_queue()
        
    
    def read_one(self, save=True):
        try:
            readed = self.serial.read(self.controller.FRAME_BYTES)
            return self.eat_frame(tuple(readed), save)
        except Exception as err:
            if len(readed) > 0:
                print("Broken frame: " + str(tuple(readed)), err)
                sleep(0.01)
            return None
        
        
    def read(self):
        while self.read_one() is not None:
            pass
        
        
if __name__ == "__main__":
    uc = UartController()
    
    print(uc.CORE_WORDS)
    print(uc.controller.FRAME_BYTES)
            
    uc.set_weight(0, 5, 10)
    uc.set_weight(1, 0, 15)
    uc.queue_changes()
    print(uc.queue)
    uc.queue_core()
    uc.flush_queue()
    uc.read()
    
    print(uc.get_weight(0, 5))
    print(uc.get_weight(1, 0))
