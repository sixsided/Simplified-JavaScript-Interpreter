package org.sixsided.scripting.SJS {
  public class VmFunc {
    public var name:String;
    public var body:Array; // of *
    public var args:Array; // of string
    public var parentScope:StackFrame;
    
    public function VmFunc(name:String, args:Array, body:Array, parentScope:StackFrame) {
        this.name = name;
        this.body = body;
        this.args = args;
        this.parentScope = parentScope;
    }   
  }
}