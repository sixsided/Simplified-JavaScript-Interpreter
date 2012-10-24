/*
Interpreter.as is a neat facade for the Simplified JavaScript classes.
*/
package org.sixsided.scripting.SJS {
  public class Interpreter {

    public var vm:VM;
    public var parser:Parser;  
    
    private var opcode_array:Array;
    public var opcode:String;
    public var ast:String;

    public function Interpreter(bootScript:String='') {
      vm = new VM();
      parser = new Parser();
      if (bootScript) {
        load(bootScript);
        run();
      }
    }
    
    public function doString(script:String) : void {
      load(script);
      run();
    }

    public function verbose() : void {
      parser.tracing = true;
      vm.tracing = true;
    }
    
    public function load(script:String):Interpreter {
      parser.parse(script);
      ast = parser.dump_ast();
      vm.load(opcode_array = parser.codegen());
      opcode = opcode_array.join(" ");
      //trace(opcode);
      return this;
    }
    
    public function run():Interpreter {
      vm.run();
      return this;
    }
    
    public function pushDict(d:Object):Interpreter {
      vm.pushdict(d);
      return this;
    }
    
    public function setGlobal(key:String, value:*):Interpreter {
      vm.set_global(key, value);// functions, variables, whatever
      return this;
    }
    
    public function setGlobals(map:Object):Interpreter {
      for(var key:String in map) {
        vm.set_global(key, map[key]);
      }
      return this;
    }
    
    
    // TODO: make this work
    // def('->', callback);
    // a -> b; // invokes callback(a, b)
    // e.g.  "EventName -> function(e) { ... };"  or even "EventName -> some statement;"
    public function defineOperator(op:String, cb:Function) : void {
      parser.defineOperator(op, cb);      
    }
    // vm.set_global('def', defineOperator);
    
  }
}