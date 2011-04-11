package org.sixsided.scripting {
  public class VmFunc {
    public var name:String;
    public var body:Array; // of *
    public var args:Array; // of string
  
    public function VmFunc(name:String, args:Array, body:Array) {
        this.name = name;
        this.body = body;
        this.args = args;
    }

  }
}