#!/bin/ash

_p1=$1
_p2=$2
_p3=$3
_p4=$4

  
# set up SOC GPIO ${_p1}, ${_p2}, ${_p3}, ${_p4} to output
echo "${_p1}" > /sys/class/gpio/export                    
echo "out" > /sys/class/gpio/gpio${_p1}/direction         
echo "${_p2}" > /sys/class/gpio/export                    
echo "out" > /sys/class/gpio/gpio${_p2}/direction         
echo "${_p3}" > /sys/class/gpio/export           
echo "out" > /sys/class/gpio/gpio${_p3}/direction
echo "${_p4}" > /sys/class/gpio/export           
echo "out" > /sys/class/gpio/gpio${_p4}/direction
                                                 
# set timing and no. cycles                      
delay=0.01                                       
cycles=64                                        
                           
# ripple across pins       
for i in $(seq $cycles)   
do                        
echo "0" > /sys/class/gpio/gpio${_p2}/value
echo "1" > /sys/class/gpio/gpio${_p1}/value
sleep $delay                               
echo "0" > /sys/class/gpio/gpio${_p3}/value
echo "1" > /sys/class/gpio/gpio${_p2}/value
sleep $delay                               
echo "0" > /sys/class/gpio/gpio${_p4}/value
echo "1" > /sys/class/gpio/gpio${_p3}/value
sleep $delay                               
echo "0" > /sys/class/gpio/gpio${_p1}/value
echo "1" > /sys/class/gpio/gpio${_p4}/value
sleep $delay                               
done                                       
                                           
# clean up                                 
echo "0" > /sys/class/gpio/gpio${_p1}/value
echo "0" > /sys/class/gpio/gpio${_p2}/value
echo "0" > /sys/class/gpio/gpio${_p3}/value
echo "0" > /sys/class/gpio/gpio${_p4}/value
echo "${_p1}" > /sys/class/gpio/unexport   
echo "${_p2}" > /sys/class/gpio/unexport   
echo "${_p3}" > /sys/class/gpio/unexport   
echo "${_p4}" > /sys/class/gpio/unexport  
