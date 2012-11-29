/*
Interpreter.as is a neat facade for the Simplified JavaScript classes.
*/
package org.sixsided.scripting.SJS {
  public class Interpreter {

    public var vm:VM;
    public var parser:Parser;  
    
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
      vm.load(parser.codegen());
      return this;
    }
    
    public function run():Interpreter {
      vm.run();
      return this;
    }
    
    public function pushDict(d:Object):Interpreter {
      vm.pushDict(d);
      return this;
    }
    
    public function setGlobal(key:String, value:*):Interpreter {
      vm.setGlobal(key, value);// functions, variables, whatever
      return this;
    }
    
    public function setGlobals(map:Object):Interpreter {
      vm.setGlobals(map);
      return this;
    }
    
    
    // TODO: make this work
    // def('->', callback);
    // a -> b; // invokes callback(a, b)
    // e.g.  "EventName -> function(e) { ... };"  or even "EventName -> some statement;"
/*    public function defineOperator(op:String, cb:Function) : void {
      parser.defineOperator(op, cb);      
    }
*/    // vm.set_global('def', defineOperator);
    
  }
}