import time 
import serial
import tkinter as tk
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, time, math
import pandas as pd

# configure the serial port

class OVEN_REFLOW_GUI:
    def __init__(self, master):
        self.master = master
        master.title("Input Parameters")
        # Create labels and input fields for each parameter
        self.com_label = tk.Label(master, text="Enter the COM port to read from:")
        self.com_label.grid(row=0, column=0)
        self.com_entry = tk.Entry(master)
        self.com_entry.grid(row=0, column=1)

        self.maxtemp_label = tk.Label(master, text="Enter the max value for y axis temp:")
        self.maxtemp_label.grid(row=1, column=0)
        self.maxtemp_entry = tk.Entry(master)
        self.maxtemp_entry.grid(row=1, column=1)
        
        self.mintemp_label = tk.Label(master, text="Enter the min value for y axis temp:")
        self.mintemp_label.grid(row=2, column=0)
        self.mintemp_entry = tk.Entry(master)
        self.mintemp_entry.grid(row=2, column=1)

        # Create a button to submit the parameters
        self.submit_button = tk.Button(master, text="Submit", command=self.submit_params)
        self.submit_button.grid(row=3, column=1)
        self.exit_button = tk.Button(master,text="Exit",command=self.exit_code)
        self.exit_button.grid(row=4, column=1)
    
    def submit_params(self):
        com_value = self.com_entry.get()
        mintemp_value = self.mintemp_entry.get()
        maxtemp_value = self.maxtemp_entry.get()
        main(com_value, mintemp_value, maxtemp_value)
    def exit_code(self):
        self.master.destroy()
        
     
def main(com_value, mintemp_value, maxtemp_value):
       
        ser = serial.Serial( 
            port=com_value,
            baudrate=115200, 
            parity=serial.PARITY_NONE, 
            stopbits=serial.STOPBITS_TWO, 
            bytesize=serial.EIGHTBITS 
        ) 
        ser.isOpen() 
        
        xsize=100

        def data_gen():
            t = data_gen.t
            while True:
               t+=1
               val=ser.readline()
               val = int(val)
               yield t, val
        t_data = []
        val_data = []
        
        def run(data):
            # update the data
            t,y = data
            if t>-1:
                t_data.append(t)
                xdata.append(t)
                val_data.append(y)
                ydata.append(y)
                if t>xsize: # Scroll to the left.
                    ax.set_xlim(t-xsize, t)
                line.set_data(xdata, ydata)
            return line
        def plot_data():  
            plt.plot(t_data, val_data)
            plt.xlabel('Time')
            plt.ylabel('Value')
            plt.xlim(min(t_data), max(t_data))
            plt.ylim(10, 240)
            plt.plot(t_data, val_data)  # Add line plot for t vs time
           
        def on_key_press(event):
            if event.key == 'q':
                ani.event_source.stop()
                plot_data()
        def on_close_figure(event):
            sys.exit(0)
            
        data_gen.t = -1
        fig = plt.figure()
        fig.canvas.mpl_connect('close_event', on_close_figure)
        fig.canvas.mpl_connect('key_press_event', on_key_press)
        ax = fig.add_subplot(111)
        line, = ax.plot([], [], lw=2)
        ax.set_ylim(mintemp_value, maxtemp_value)
        ax.set_xlim(0, xsize)
        ax.set_xlabel('Data Points')
        ax.set_ylabel('Temperature')
        ax.grid()
        xdata, ydata = [], []
        # Important: Although blit=True makes graphing faster, we need blit=False to prevent
        # spurious lines to appear when resizing the stripchart.
        ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, 
        repeat=False)
        plt.show()

# Create the GUI window
root = tk.Tk()
input_params_gui = OVEN_REFLOW_GUI(root)

# Start the GUI event loop
root.mainloop()

