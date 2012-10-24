/*
  Helpful hints:
    serve policy files on Flash's expected port 843 with:   
      while true ; cat policy.xml | nc -l 843 ; end
      
    listen for connections from the Flash app with:
      rlwrap nc -lk 8080    
*/
package org.sixsided.scripting.SJS {
  
  import flash.net.Socket;
  import flash.events.Event;
  import flash.events.ProgressEvent;
  import flash.events.ErrorEvent;
  import flash.events.IOErrorEvent;
  import flash.utils.getQualifiedClassName;

  public class RemoteConsole {
    
    protected var socket:Socket;
    protected var interpreter:Interpreter;    
    protected var helloMessage:String = null;

    public function RemoteConsole(host:String, port:int, helloMessage:String) {
      super();
      this.helloMessage = helloMessage;
      connect(host, port);
    }
    
    public function connect(host:String, port:int) : void {
        var s:Socket = this.socket = new Socket();
        s.addEventListener(Event.CONNECT, evtConnect);
        s.addEventListener(Event.CLOSE, evtClose);
        s.addEventListener(IOErrorEvent.IO_ERROR, evtIOError);
        s.addEventListener(ErrorEvent.ERROR, evtError);
        s.addEventListener(ProgressEvent.SOCKET_DATA, evtData);
        trace('RemoteConsole connecting to ', host, port, ':', s);
        s.connect(host, port);
    }

    
    protected function evtConnect(e:Event):void {
      trace('evtConnect (RemoteConsole connected)', e);
      sendBack('@flash');
      
      if(helloMessage) { sendBack(helloMessage); }
    }
    
    protected function evtClose(e:Event):void {
      trace('evtClose', e);
    }
    protected function evtIOError(e:IOErrorEvent):void {
      trace('evtIOError', e);
    }
    protected function evtError(e:ErrorEvent):void {
      trace('evtError', e);
    }
    
    private var buffer:String = '';
    
    protected function evtData(e:ProgressEvent):void {
      var data:String = this.socket.readUTFBytes(this.socket.bytesAvailable);
      //trace('read from socket: "' + data + '"');
      if(interpreter) {
        try {
          /*
          // semicolon insertion
            if(!data.match(/\s*;\s*$/)) {
              data += ';';
            }
            interpreter.doString(data);
          */

          // semicolon as terminator
          if(data.match(/;\s*$/)) {
            try {
              interpreter.doString(buffer + data);
            } catch(e:*) {
              trace(e);
              trace(e.getStackTrace());
              sendBack(e);
            } finally {
              buffer = '';
            }
          } else {
            buffer += data;
          }
        } catch(e:*) {
          trace(e);
        }
      }
    }
    
    public function sendBack(s:String) : void {
      this.socket.writeUTFBytes(":   " + s.split("\n").join("\n    ") + "\n"); // ignore outputProgressEvent
    }
    
    public function rcTrace(...args) : void{
           trace("[Interpreter]", args.join(" "));
           sendBack(args.join(', '));
    }
    
    public function rcInspect(v:*) : void { 
      rcTrace(getQualifiedClassName(v), Inspector.inspect(v)); 
    }
    
    public function rcHelp() : void {
      function keys(o:Object):String {
        var ret:String = '';
        for(var k:String in o) {
          ret += k + "\n";
        }
        return ret;
      }
      
      rcTrace("=== Static Registry ===\n" + keys(VM.registry));
      rcTrace("=== Globals ===\n" + keys(interpreter.vm.vm_globals));
      //rcTrace("=== dict #" + i + " ===\n" + keys(vm.system_dicts[i]));
    }
    
    
    public function setInterpreter(i:Interpreter)  : void {
      interpreter = i;
      interpreter.vm.set_global('trace', rcTrace);
      interpreter.vm.set_global('_', rcInspect);
      interpreter.vm.set_global('help', rcHelp);           
      // interpreter.setGlobals({trace_on : interpreter.parser.trace_on, trace_off :  interpreter.parser.trace_off});           
      //interpreter.parser.trace_on();
      //interpreter.vm.system_dicts[0].trace = this.rcTrace;
      //interpreter.vm.system_dicts[0]._ = function(v:*) { rcTrace(Inspector.inspect(v)); };
    }
  }
}