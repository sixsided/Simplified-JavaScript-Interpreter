package org.sixsided.scripting.SJS {
  
  /* A function call frame, with its own program counter and local variables.
     Function calls are the only use of callframes in this VM.  (As opposed to org.sixsided.fith, which uses them for 
     loops.)
   */
   import org.sixsided.scripting.SJS.Inspector;
  
  public class StackFrame {
    public var code:Array;
    public var pc:Number;
    public var exhausted:Boolean;
    public var vars:Object;
    
    function StackFrame(code:Array,vars:Object=null) {
      this.code = code;
      this.pc = 0;
      this.exhausted = false;
      this.vars = vars || {};
    }
  
    public function next_word(){      
        // this check is here because we want to return control to run and let it finish out the current
        // iteration *before* we exhaust the call frame.  The last word might be a JUMP back to the start of the frame.
        if(this.pc >= this.code.length) {
          // console.warn('exhausted StackFrame');
          this.exhausted = true;  
          return VM.NOP; // fixme reference Opcode table object
        }

        // console.log('StackFrame.next_word', this.pc, this.code[this.pc]);
        var word = this.code[this.pc++];
        return word;    
    }
    
    public function toString(){
      var str:String = '';
      for(var k in vars) str += k + ' : ' + Inspector.inspect(vars[k]) + "\n";
      return str;
    }
  }
}