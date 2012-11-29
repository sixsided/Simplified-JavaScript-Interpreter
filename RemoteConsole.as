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
    
    protected var _verboseCodegen:Boolean = true;
    protected var _verboseParse  :Boolean = true;

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
    
    private function formatStackTrace(e:*) : String {
      
      // turn noisy lines like this:
      //        at org.sixsided.scripting.SJS::Parser/expression()[/Users/miles/Documents/Flash/classes/org/sixsided/scripting/SJS/Parser.as:472]
      // into this:
      //         at org.sixsided.scripting.SJS::Parser/expression()[Parser.as:472]
      //         Parser/expression()[Parser.as:472]
      
      var txt:String = e.getStackTrace();
      var lines:Array = txt.split("\n");
      var head:String = lines[0];
      var body:String = lines.slice(1).join("\n");
      
      /*body.replace(/at .*::/g, '').replace(/\[(.*):/g, '[\1')*/
      body = body.replace(/at .*::/g, '').replace(/\[.*\/(.*):/g, "[$1:");


      /*
      TBD: split on "[" and align [File.as:lineNum] to same tab stop
      var margin:Number = 0;
      lines.slice(1).forEach(function(e:String) { acc = Math.max(acc, e.indexOf('[')); });
      */


      return head + "\n" + body;
    }
      
    
    protected function evtData(e:ProgressEvent):void {
      var data:String = this.socket.readUTFBytes(this.socket.bytesAvailable);
      //trace('read from socket: "' + data + '"');
      if(interpreter) {
        /*try {*/
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
              trace("RemoteConsole::evtData -> doString:", formatStackTrace(e));
              sendBack(e);
            } finally {
              buffer = '';
              /*if(_verboseParse) {
                rcTrace(interpreter.parser.dump_ast());
              }
              if(_verboseCodegen) {
                rcTrace(interpreter.parser.dbg_codegen_string());
              }*/
            }
          } else {
            buffer += data;
          }
        /*} catch(e:*) {
          trace("RemoteConsole::evtData(trying to match string)", e);
        }*/
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
    
    public function rcVerboseParse(on:Boolean) : void {
      _verboseParse = on;
    }
    
    public function rcVerboseCodegen(on:Boolean) : void {
      _verboseCodegen = on;
    }
    
    
    public function setInterpreter(i:Interpreter)  : void {
      interpreter = i;
      interpreter.setGlobals({'trace': rcTrace,
                              '_': rcInspect,
                              'help': rcHelp,           
                              'verbose_parse': rcVerboseParse,           
                              'verbose_codegen': rcVerboseCodegen
                             });                 
    }
  }
}