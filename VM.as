/*  VM
  Execute the compiled bytecode.  Inspired heavily by JonesFORTH, to a lesser degree by Postscript and HotRuby.

See:
  http://replay.waybackmachine.org/20090209211708/http://www.annexia.org/forth

Notes to self:
  The Array class is one of the few core classes that is not final, which
  means that you can create your own subclass of Array. Hmmm.... probably a bad idea.

*/

package org.sixsided.scripting.SJS {
  import org.sixsided.scripting.SJS.Inspector;
  import flash.utils.getDefinitionByName;
  import flash.utils.getQualifiedClassName;
 
  import flash.geom.*;
  import flash.display.*;
  import org.sixsided.util.Promise;
  import org.sixsided.util.ANSI;  

  import flash.events.Event;
  import flash.events.EventDispatcher;
  
  public class VM extends EventDispatcher {

    public static var _VM_ID:int = 0;
    public static var registry:Object = { Math:Math, Date:Date, 'null':null }; // TweenLite, etc goes here

    public static function register(key:String, value:*) : void {
      VM.registry[key] = value;
    }


   public static const MAX_RECURSION_DEPTH : int = 64;
       
  /***********************************************************
  *
  *    OPCODE IDs
  *
  ***********************************************************/

      public static const NOP:String         = 'NOP';
      public static const DUP:String         = 'DUP';
      public static const DROP:String        = 'DROP';
      /*public static const DROPALL:String        = 'DROPALL';*/
      public static const SWAP:String        = 'SWAP';
      public static const INDEX:String       = 'INDEX';
      public static const LIT:String         = 'LIT';
      public static const VAL:String         = 'VAL';
      public static const ADD:String         = 'ADD';
      public static const SUB:String         = 'SUB';
      public static const MUL:String         = 'MUL';
      public static const DIV:String         = 'DIV';
      public static const MOD:String         = 'MOD';
      public static const NEG:String         = 'NEG';
      public static const EQL:String         = 'EQL';
      public static const GT:String          = 'GT';
      public static const LT:String          = 'LT';
      public static const GTE:String         = 'GTE';
      public static const LTE:String         = 'LTE';
      public static const AND:String         = 'AND';
      public static const OR:String          = 'OR';
      public static const NOT:String         = 'NOT';
      public static const CLOSURE:String     = 'CLOSURE';
      public static const MARK:String        = 'MARK';
      public static const CLEARTOMARK:String        = 'CLEARTOMARK';
      public static const ARRAY:String       = 'ARRAY';
      public static const HASH:String        = 'HASH';
      public static const JUMP:String        = 'JUMP';
      public static const JUMPFALSE:String   = 'JUMPFALSE';
      public static const CALL:String        = 'CALL';
      public static const RETURN:String      = 'RETURN';
/*    public static const TRACE:String       = 'TRACE';*/
      public static const PUT:String         = 'PUT';
      public static const PUTINDEX:String    = 'PUTINDEX';
      public static const GETINDEX:String    = 'GETINDEX';
      public static const GET:String         = 'GET';
      public static const LOCAL:String       = 'LOCAL';
      public static const NATIVE_NEW:String  = 'NATIVE_NEW';
      public static const AWAIT:String       = 'AWAIT';
      public static const PUSH_RESUME_PROMISE:String       = 'PUSH_RESUME_PROMISE';
      //public static const HALT:String        = 'HALT';


      /***********************************************************
      *
      *    EVENTS
      *
      ***********************************************************/
      public static const EXECUTION_COMPLETE:String = 'VM.EXECUTION_COMPLETE';
     

         
    /***********************************************************
    *
    *    VM STATE
    *
    ***********************************************************/
     public var _vm_id:String = ""+_VM_ID++;;

     public var running:Boolean;
     public var tracing:Boolean = false;
    
     
     public var call_stack:Array = []; // function call stack    
     public var os:Array = [];         // operand stack
     public var marks:Array = [];      // stack indices for array / hash construction
     
     public var system_dicts:Array = [];  // context; e.g. add a movie clip and script "x += 10"
     public var vm_globals:Object = {};  // global scope, like you're used to in browser JavaScript:
    
        
  /************************************************************
  **
  **        PRIVATE API
  **
  ************************************************************/    
  
    private function log(...args) : void {
      if(tracing) {
        _vmTrace('| ' +  args.join(' '));
      }
    }


    private function _vmTrace(...args) : void {
      trace('[VM#'+_vm_id+']', args.join(' '));
    }
    
    
    private function _vmUserTrace(...args) : void {
      _vmTrace(ANSI.cyan(args.join(' ')));
    }

    private function get _osAsString() : String {
      return os.map(function(e:*, ...args) : String { 
        if (e is Function) { return '*fn*'; } return e; 
      }).join(' ');
    }
    
    
    private function next_word() : * {
      return current_call.next_word();
    }

    private function get current_call():StackFrame { 
      return call_stack[0]; 
    }
    
 
  /***********************************************************
  *
  *   PUBLIC API
  *
  ***********************************************************/

    public function VM() {
        setGlobal('trace', _vmUserTrace);
        setGlobal('halt', halt);          
    }

  // for hotloading -- define a "clone me" function externally
  // but make it a noop in the clone so you don't get
  // infinite recursion
/*    public function clone() : VM {
          var ret:VM = new VM;
          ret.load(call_stack[0].code);
          return ret;
    }
*/
    public function setGlobal(k:String, v:*) : void {
      vm_globals[k] = v;
    }


    public function setGlobals(o:Object) : void {
      for(var k:String in o) vm_globals[k] = o[k];
    }


    public function pushDict(dict:Object) : void {
      system_dicts.unshift(dict);
    }

    // can say vm.load(one_liner).run() with no trouble
    // prebind the ops for speed?
    public function load(tokens:Array) : VM {
        call_stack = [ new StackFrame(tokens, {}) ];
        return this;
    }

    public function loadString(code:String) : VM {
      load(code.split(' '));
      return this;
    };

      
    public function halt() : void {
      running = false;
    }
    
        
    

    // == run ==
    // some notes:
    // Opcodes can only legally be of type String, although we interleave other types of data with them.
    // we loop until reaching the end of the last stack frame, or until halted (running = false).
    // we wrap (op) in extra parentheses to quiet Flash's "function where object expected" warning.
    // we stash the callframe at the top of the inner loop in case next_word exhausts the StackFrame, causing it to be popped at the end of the loop

    // have to do checks in loop in case we:
    //    - popped a frame last time through
    //    - exhausted callframe during run loop -- probably if/else jumping to end
    

        //trace('VM.run; call_stack depth:', cs.length, 'pc @', cs[0].pc, '/', cs[0].code.length, '(', cs[0].code.join(' '), ')');
        //trace('... bailing at end of cycle, call_stack depth:', cs.length, 'pc @', cs[0].pc, '/', cs[0].code.length, '(', cs[0].code.join(' '), ')');
        // log('    VM Finished run. os: ', '[' + os.join(', ') + ']', ' dicts: ', Inspector.inspect(system_dicts), 'traces:', Inspector.inspect(dbg_traces), "\n");
        //log(w, ANSI.wrap(ANSI.BLUE, ' ( ' + _osAsString + ' ) '));
        
    
    public function run() : void {
      var cs:Array = call_stack;
      var op:Function;
      
      running = true;

      while(cs.length) {
        while(cs.length && !current_call.exhausted && running) {                        
          op = this[current_call.next_word()];
          if(!(op)) {
            if(current_call.exhausted) continue;
            else throw new Error('VM got unknown operator ``' + current_call.prev_word() + "''");
          }
          
          op();
          
          if(!running)  return; // bail from AWAIT instruction

        }
        cpop(); // automatically return at end of function even if no return statement
      }
      
      running = false;
      dispatchEvent(new Event(EXECUTION_COMPLETE));
    }
    
    public function onComplete(fn:Function) : void {
        addEventListener(EXECUTION_COMPLETE, function _doOnComplete(...args) : void {
            removeEventListener(EXECUTION_COMPLETE, _doOnComplete);
            fn();
        });
    }

        
        
/**************************************************
**
**              INTERNALS
**
***************************************************/
        
    


// call_stack manipulation.  We prefer unshift/shift to push/pop because it's convenient that top-of-stack is always stack[0]
    private function cpush(code:Array,vars:Object) : void { 
      call_stack.unshift(new StackFrame(code, vars, call_stack[0])); 
    }


    private function cpop() : void { 
      call_stack.shift(); 
    }


    private function fcall(fn:VmFunc, args:Array) : void {
      if(call_stack.length > VM.MAX_RECURSION_DEPTH) { 
        throw new Error('org.sixsided.scripting.SJS.VM: too much recursion in' + fn.name);
      }

      call_stack.unshift(new StackFrame(fn.body,
                                        conformArgumentListToVmFuncArgumentHash(args, fn),
                                        fn.parentScope));
    }

// stack manipulation

    
    private function opush(op:*):void { os.unshift(op); log(op, '->', '(', _osAsString, ')'); };
    private function opop():* { log(os[0], '<-', '(', _osAsString, ')'); return os.shift(); };
    private function numpop():Number { return parseFloat(opop()); };
    private function bin_ops():Array { return [opop(), opop() ].reverse(); };
    private function pushmark():void { marks.unshift(os.length); };
    private function yanktomark():Array{ return os.splice(0, os.length - Number(marks.shift())).reverse();  }; // fixme: hack, ditch shift-stacks for push-stacks
    
// var manipulation


      /*    find_var/set_var
       *  VM has four tiers of variables.
       *  1) the chain of StackFrame vars as defined by lexical scope
       *  2) the VM's globals, vm_globals
       *  3) the system dicts, in the order they were added -- READ ONLY; set_var does not even look at these
       *  4) the VM's static registry, VM.registry
       *  
       *  *** The only writable vars are the current callframe's and the vm globals
       *  *** ... that is, locals and globals for a given VM.  Just like Javascript.
       *  ....... Could add a 'register' function for adding things to the registry.
       */

       // so running in the root scope, the 'var' keyword indicates a temporary variable tha won't persist after
       // the call_stack is exhausted, i.e. the code runs through to its end and the vm exits.
       // simply setting a variable with x = n, however, will create a persistent global x.
       
      private function frameWithVar(key:String) : StackFrame {
        var sf:StackFrame = call_stack[0];
        var safety:int = MAX_RECURSION_DEPTH;
        while(sf && safety--) {          
          if(sf.vars.hasOwnProperty(key)) {
            return sf;
          }
          sf = sf.parent;
        }
        return null;                  
      }
      
      
      public function set_var(key:String, value:*) : void {
        var sf:StackFrame = frameWithVar(key);
        if(sf) {
            sf.vars[key] = value;
            return;
        }
        vm_globals[key] = value;
      };
  
    
      public function findVar(key:String) : * {      
        var v:* = _find_var(key);
        return (undefined === v) ? null : v;  // duhh why?
      }
  
  
      private function _find_var(key:String) : * {
        // locals?
        var sf:StackFrame = frameWithVar(key);
        if(sf) {
          return sf.vars[key];
        }
        
        // globals?
        if(vm_globals.hasOwnProperty(key)) {
          return vm_globals[key];        
        }

        // dicts?  (in LIFO order)
        for (var i:int = 0; i < system_dicts.length; i++) {
          var g:Object = system_dicts[i];
          if(g.hasOwnProperty(key)) {
            return g[key];
          }
        }
        
        // registry?
        if(VM.registry.hasOwnProperty(key)) {
          return VM.registry[key];
        }
        
        // not defined anywhere!
        return undefined;
      };



  /***********************************************************
  *
  *    OPCODES
  *
  ***********************************************************/
  

        public function callScriptFunction(fnName:String, args:Array=null) : void {
          _vmTrace('callScriptFunction', fnName);
          var fn:* = findVar(fnName);
          if(fn is Function) {
            fn.apply(null, args);
          } else if(fn is VmFunc) {
            fcall(fn, args);
            run();
          } else {
            throw "Tried to callScriptFunction on object "  + fn;
          }
        }


        // wrap VM functions in AS3 closures so we can pass them to AS3
        // as event listeners, etc, that will fire up the vm
        private function wrapVmFunc(fn:VmFunc):Function{
          var vm:VM = this;
          return function(...args):void {
            vm.fcall(fn, args);
            vm.run(); // if called from within SJS code, recurses into VM::run(); if called from an AS callback, starts up the interpreter
          }
        }  
        
        
        // fixme: replace for/in with for(i...
        private function conformArgumentListToVmFuncArgumentHash(func_args:Array, fn:VmFunc):Object {
          var ret:Object = {};
          for (var i:String in fn.args) {
            var k:String = fn.args[i];
            ret[k] = func_args.shift();
          }
          return ret;
        }
    
    
        private function NOP():void { }

        //stack manipulation
        private function DUP()   :void{ var p:* = opop(); opush(p); opush(p); }
        private function DROP()  :void{ opop(); }
        private function CLEARTOMARK()  :void{ yanktomark(); }
        private function SWAP()  :void{ var a:* = opop(); var b  : * = opop(); opush(a); opush(b); }
        private function INDEX() :void{ var index :*= opop(); opush(os[index]); }

        //values
        private function LIT():void{   var v:* = next_word();  opush(v);  }
        private function VAL():void{   opush(findVar(next_word())); }

        //arithmetic
        private function ADD():void{      var o:Array = bin_ops(); opush(o[0] + o[1]); }
        private function SUB():void{      var o:Array = bin_ops(); opush(o[0] - o[1]);}
        private function MUL():void{      var o:Array = bin_ops(); opush(o[0] * o[1]); }
        private function DIV():void{      var o:Array = bin_ops(); opush(o[0] / o[1]); }
        private function MOD():void{      var modulus:Number = numpop(); opush(numpop() % modulus); } 
        private function NEG():void{      opush(-opop()); }

        //relational
        private function EQL():void{ opush(opop() == opop());                      }
        private function GT() :void{ var o:Array = bin_ops(); opush(o[0] > o[1]);  }
        private function LT() :void{ var o:Array = bin_ops(); opush(o[0] < o[1]);  }
        private function GTE():void{ var o:Array = bin_ops(); opush(o[0] >= o[1]); }
        private function LTE():void{ var o:Array = bin_ops(); opush(o[0] <= o[1]); }

        //short-circuit logic operators -- for a() && b(), don't evaluate b() if a is falsy
        // for a() || b(), don't evaluate b if a is truthy
        private function _short_circuit_if(value:Boolean):void {
          var right:*= opop();
          var left:*= opop(); 
          if(!!left == value) {
            opush(left);
          } else {
            cpush(right, {}); 
            // Creates a callframe/scope.  
            // "a && v = 3" will set v in global scope if not defined in the enclosing scope.
          }
        }
        
        private function AND():void{ _short_circuit_if(false); }
        private function OR():void { _short_circuit_if(true); }
        private function NOT():void{ opush(!opop()); }


        //structures
        private function MARK():void {  pushmark(); }
        private function ARRAY():void { opush(yanktomark()); }
        private function HASH():void {
              var i:int, dict:Object = {}, a:Array = yanktomark(); 
              for(i=0; i < a.length; i+=2) {
                dict[a[i]] = a[i+1];
              }
              opush(dict);
        }
      

        //flow control
        private function JUMP():void{ 
            current_call.pc += next_word();
        }
        private function JUMPFALSE():void{ 
            var prevpc:int = current_call.pc;
            var offset:int = next_word();
            if(!opop()) {
                current_call.pc += offset;
            }
        }



        //functions
        private function CLOSURE():void{ 
            var closure:Function;
            log(Inspector.inspect(os));
            var body:Array= opop();
            var args:Array= opop();
            var name:String = opop();

            // used to wrap vm functions in AS3 functions here

            var vmf:VmFunc = new VmFunc(name, args, body, call_stack[0]);
            set_var(name, vmf);
            opush(vmf);
        }
        

          // TODO -- supply a "this" context for scripted functions?
          // FIXME -- How to distinguish between functions returning nothing and functions
          //          returning undefined? For now, we don't.
          // we allow both wrapped and unwrapped functions because they're both useful:
          //  wrapped functions for passing to AS3 as e.g. event listeners which retain
          //  a reference to this VM in their closures;
          // unwrapped functions so we can run code from another VM in our own context
         private function CALL():void { // (closure args_array -- return_value 
            var func_args:* = opop();
            var fn:* = opop();
            var rslt:*;
            
            if(fn is Function) {
                rslt = fn.apply(null, func_args);
                if(rslt !== undefined) opush(rslt); 
            } else if(fn is VmFunc) {
                fcall(fn, func_args);              
            } else {
                trace('* * * * * VM.CALL tried to call nonfunction value "' + fn + '": ' + typeof(fn) + ' * * * * * *');
            }
         }
     
     
         private function RETURN():void{ 
           log('return');
           cpop();
         }


        // getting and setting values        
        private function GET ():void {
          var key:String = opop();    
          opush(findVar(key));
        }


        // v k PUT
        private function PUT():void{  // (value key -- value )
          var key:String = opop();
          var value:* = opop();
          log('PUT', value, key);
          set_var(key, value);
          // opush(value);
        }


        private function PUTLOCAL():void{  // (value key -- value )
          // TODO: figure out scopes in parser/codegen
          //       or just generate PUTLOCAL anywhere you see "var x;" (gets null or undefined) or "var x = value":
          var key:String = opop();
          var value:* = opop();
          log('PUTLOCAL', value, key);
          call_stack[0].vars[key] = value;
          
          // opush(value);
        }


        // value object key PUTINDEX
        private function PUTINDEX():void{  // ( value object key -- value )
          var key   :* = opop();
          var object:* = opop();
          var value :* = opop();
          object[key] = value;
          // opush(value);
        }


        private function GETINDEX():void{  // aka "dot"  (o k -- o[k])
            var k:* = opop();
            var o:* = opop();
            // trace('GETINDEX', o, k);            
            opush(o[k]);
        }


        // LIT m LOCAL -- declares m as a var in current scope
        private function LOCAL():void {
          var key:String = opop();    
          current_call.vars[key] = undefined;
        }


        // NEW   ( constructor [args] -- instance )
        private function NATIVE_NEW():void {            
            var args:Array = opop();
            var classname:String = opop();
            var klass:Class = findVar(classname);
            var instance:*;

            log('++ new ', classname, '(' + args.join(', ') + ')  //', klass + ': ' + getQualifiedClassName(klass));
            
            switch(args.length) {
              case 0: instance = new klass(); break; 
              case 1: instance = new klass(args[0]); break; 
              case 2: instance = new klass(args[0], args[1]); break; 
              case 3: instance = new klass(args[0], args[1], args[2]); break; 
              case 4: instance = new klass(args[0], args[1], args[2], args[3]); break; 
              case 5: instance = new klass(args[0], args[1], args[2], args[3], args[4]); break; 
              case 6: instance = new klass(args[0], args[1], args[2], args[3], args[4], args[5]); break;
              case 7: instance = new klass(args[0], args[1], args[2], args[3], args[4], args[5], args[6]); break;
              case 8: instance = new klass(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]); break;
              case 9: instance = new klass(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8]); break;
              default: throw "NATIVE_NEW was given too many arguments: " + args.length;
            }       
            opush(instance);            
        }


        private function _resumeFromPromise(...promiseFulfillArgs) : void {
          trace('_resumeFromPromise', promiseFulfillArgs);
          // convert all cases to 1-arg.
          //    0: null
          //    1: pass through
          //    N: pass as an array 

          if(promiseFulfillArgs.length == 0) {
            opush(null);
          } else if(promiseFulfillArgs.length == 1) {
            opush(promiseFulfillArgs[0]);
          } else {
            opush(promiseFulfillArgs);
          }

          run();
        }
        
        private function AWAIT():void {
          var p:Promise = opop();
          halt();
          p.onFulfill(_resumeFromPromise);
        }
        
    } // VM
  
} // package
