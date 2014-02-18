#!/usr/bin/env python
import sys
import SocketServer, socket
import re

"""
  This provides a "chat" server that both telnet and Flash's NetSocket can connect to.
  Clients can tag themselves a being in a group by sending "@NameOfGroup".
  Any other messages sent will be echoed to all clients in /differing/ groups.


	I mainly built this so I wouldn't have to keep entering "nc -l 9000" every
	time I restarted the Flash app. You just telnet to the hub once and you're good
	for any number of invocations of your Flash app.

  Usage:
    Connect from AS3 with NetSocket, and send "@flash"
    Connect from any number of terminals with "nc localhost 9000".
    Use "rlwrap nc localhost 9000" to give yourself command-line history.

    The chat server has one command, "@", which you use like this:
    
      @applesauce
      
    adds you to the group "applesauce", which means you will see 
    only messages from clients which are *not* in that group.
    
    Thanks to the terminals being in the @default group, they won't
    see each others' messages, but all will see flash's messages.

"""


port_num = 9000;

userlist  = {} # {request, channel}

class MyHandler(SocketServer.BaseRequestHandler):
  def setup(self):
    # print " === SocketServer MyHandler.setup === "
    userlist[self.request] = 'default';
    # print userlist;
    
  def handle(self):
    while(True):
      try:
        # request, client_address, server
        data = self.request.recv(1024)  # blocks until read
        if(len(data) == 0):
          raise
          
        print userlist[self.request], ':"' + data.strip() +'"'          
        
        match = re.match('^@(\w+)', data)
        
        if not match:
          self.broadcast(data)
        else:
          channel = match.group(1)
          userlist[self.request] = channel
          print("   [switched channel to %s]" % (channel)) 
          
          # allow for one-liners like "echo '@someChannel|doSomething' | nc localhost 9000"
          lines = data.split("|")
          if len(lines) > 1: 
            self.broadcast(lines[1])
            print userlist[self.request], ':"' + lines[1].strip() +'"'           

      except:
        # no data, disconnect
        # print "Closing request", self.request
        print "CLOSE", userlist[self.request]
        userlist.pop(self.request)
        self.request.close()
        return
    
  def broadcast(self, msg):    
    for rq in userlist: 
      if userlist[rq] != userlist[self.request]:
         rq.send(msg)
    

class MyThreadingTCPServer(SocketServer.ThreadingTCPServer): 
  allow_reuse_address = True


print " === starting server on port", port_num, " ==="
ss = MyThreadingTCPServer(('localhost', port_num), MyHandler);
ss.serve_forever();
