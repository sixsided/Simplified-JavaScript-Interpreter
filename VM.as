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

  import flash.events.Event;
  import flash.events.EventDispatcher;
  
  public class VM extends EventDispatcher {
/*
**       
**      ERRORS
**
*/
    //   ACCESSED_UNDECLARED_VAR
    //   CALLED_NONFUNCTION_VALUE
       
/*
**       
**      OPCODES
**
*/

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
      /*public static const CLEARTOMARK:String        = 'CLEARTOMARK';*/
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
      //public static const HALT:String        = 'HALT';


      // event constants
      public static const EXECUTION_COMPLETE:String = 'VM.EXECUTION_COMPLETE';
      
/*
**       
**          STATIC VARS, METHODS
**
*/

    public static var registry:Object = {}; // for importing Tweener, etc.   formerly 'uber_globals'
    //public static var dbg_last_vm:VM;          // debugging hack

    public static function register(key:String, value:*) : void {
      //trace('VM::register(',key,', ', value, ')');
      VM.registry[key] = value;
    }

    //static function dbg_dump_os(){
    //  return Inspector.inspect(VM.dbg_last_vm.os);
    //};
  
    
         
  /***********************************************************
  *
  *    INSTANCE VARS, GETTERS -- VM STATE
  *
  ***********************************************************/

     // VM state
     public var running:Boolean;
    
     // function call stack    
     public var call_stack:Array = []; // of StackFrame
     
     // operand stack (like in an RPN calculator)
     public var os:Array = [];
     // stack indices for array / hash construction
     public var marks:Array = []; 
     
     // HACK, system dictionaries to allow the VM to operate in the context of another object
     // such as a MovieClip, etc. So you can write "x += 10" and the containing MC will move 10 pixels right.
     public var system_dicts:Array = [];  /* public so InterpreterHarness can jam stuff into it */     

     // global scope, like you're used to in browser JavaScript:
     public var vm_globals:Object = {};

     // recursion limit
     public static const MAX_RECURSION_DEPTH : int = 64;
     public var depth:Number = 0; 
    
     public var tracing:Boolean = false;


    private function get callframe():StackFrame { return call_stack[0]; }
    
  /************************************************************
  **
  **        TEST / DEBUG SUPPORT
  **
  ************************************************************/    

    public var dbg_traces:Array = []; // read this out in your tests.

    public function inject_globals(o:Object) : void {
      // !!! for testing only, as it'll overwrite existing globals
      for(var k:String in o) vm_globals[k] = o[k];
      
/*      trace('injected globals with ', Inspector.inspect(o), ' yielding: ', Inspector.inspect(system_dicts));*/
    };
    public function set_global(k:String, v:*) : void {
      //trace('set_global', k, v);
      vm_globals[k] = v;
    }
    


  /***********************************************************
  *
  *   PUBLIC API
  *
  ***********************************************************/


    public function VM() {
        //VM.dbg_last_vm = this;
        // FIXME: trace should probably be injected from the test suite -- this may be useful for debugging, though.
        // Will need a listener or something for getting at the traces.
        //var self:VM = this;
        /*set_global('trace', vmTrace);*/
        set_global('halt', halt);
        set_global('Math', Math);
        set_global('Date', Date);
        set_global('null', null);
        // set_global('undefined', undefined);        

        //system_dicts = [{  'trace':function():void { 
        //                     trace('[SJS] ', arguments); 
        //                     dbg_traces.push(arguments); 
        //                   },
        //                 
        //                   'halt':function():void { 
        //                     self.halt(); 
        //                   }}];
          
    }
    
    /*public function vmTrace():void {
      trace('[SJS] ', arguments); 
      dbg_traces.push(arguments); 
    }*/

    public function pushdict(dict:Object) : void {
      system_dicts.push(dict);
    }
    
    public function load_opcode_string(code:String) : VM {
      // for debugging, testing
      load(code.split(' '));
      return this;
    };

    // can say vm.load(one_liner).run() with no trouble
    public function load(tokens:Array) : VM {
        call_stack = [ new StackFrame(tokens, {}) ]; // TBD: replaced save_globals with {}, verify that this works with "var x" statements in one-liners
        // optimization idea: call_stack = [ new StackFrame(this._prebind_ops(tokens), {}) ];
        //trace('VM Load: [' + tokens.join(' ') + ']');
        return this;
    }

  
    public function log(...args) : void {
      if(tracing) {
        trace('| ' +  args.join(' '));
      }
    }
      
    public function halt() : void {
      log('~~halt at ', call_stack[0].pc);
      running = false;
    }

    public function run() : VM {
      var e:Error;
      var cs:Array = call_stack;
      trace('VM.run; call_stack depth:', cs.length, 'pc @', cs[0].pc, '/', cs[0].code.length, '(', cs[0].code.join(' '), ')');
      running = true; // HALT operator can stop it.  Just call vm.run() to resume;
   //   try { 
        while(cs.length) {
          // Run until reaching end of last stack frame, or until halted.
          while(cs.length && !cs[0].exhausted && running) {                        
            var cf:StackFrame = cs[0];     // stash it in case next_word exhausts it, causing it to pop off at the end of this while loop
            var w:String = cf.next_word(); // Opcodes can only legally be of type String, although we interleave other types of data with them.
            var op:Function = this[w];
            if(cs[0].exhausted && !(op)) { // extra parentheses to quiet Flash's "function where object expected" warning
               continue;  // exhausted callframe during run loop -- probably if/else jumping to end
            }
            if(!(op)) {
              throw new Error('VM got unknown operator ``' + w ); // + "'' in [" + cs[0].code.join(',') + ']');              
            }
            log(w, ' ( ', os.join(' '), ' ) ', '# '+os.length);
            op();
            if(!running) {
              /*trace('... bailing at end of cycle, call_stack depth:', cs.length, 'pc @', cs[0].pc, '/', cs[0].code.length, '(', cs[0].code.join(' '), ')');*/
              return this; // bail from AWAIT instruction
            }
          }
          cpop();
        }
 /*   
      } catch(e) {
        throw new Error("VM caught exception on word `" + w + "`: ``" + e + "'', current callframe: " + Inspector.inspect(callframe) );
      }
*/
      log('    VM Finished run. os: ', '[' + os.join(', ') + ']', ' dicts: ', Inspector.inspect(system_dicts), 'traces:', Inspector.inspect(dbg_traces), "\n");
      running = false;
      dispatchEvent(new Event(EXECUTION_COMPLETE));
      return this;
    };
    
        
          // debug
          // function get os () {
          //   return os;
          // };
          // 
          // function get call_stack() {
          //   return call_stack;
          // };
          // 
          // function get dbg_traces() {
          //   return dbg_traces;
          // };
          // function get dbgLastCallframe() {
          //   return dbgLastCallframe;
          // }
        
        
/**************************************************
**
**              INTERNALS
**
***************************************************/
        
    


// call_stack manipulation.  We prefer unshift/shift to push/pop because it's convenient that top-of-stack is always stack[0]
    private function cpush(code:Array,vars:Object, parent:StackFrame=null) : void { 
      depth++; 
      call_stack.unshift(new StackFrame(code,vars, parent || call_stack[0])); 
    };
    private function cpop() : void { 
      depth--; 
      call_stack.shift(); 
    };

// stack manipulation
    private function get _osAsString() : String {
      return os.map(function(e:*, ...args) : String { if (e is Function) { return '*fn*'; } return e; }).join(' ');
    }
    
    public function opush(op:*):void { log(op, '->', '(', _osAsString, ')'); os.unshift(op); };
    public function opop():* { log(os[0], '<-', '(', _osAsString, ')'); return os.shift(); };
    public function numpop():Number { return parseFloat(opop()); };
    public function bin_ops():Array { return [opop(), opop() ].reverse(); };
    public function pushmark():void { marks.unshift(os.length); };
    public function yanktomark():Array{ return os.splice(0, os.length - Number(marks.shift())).reverse();  }; // fixme: hack, ditch shift-stacks for push-stacks
    
// var manipulation


      /*    find_var/set_var
       *  VM has four tiers of variables.
       *  1) the curent call frame's vars
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
      public function set_var(key:String, value:*) : void {
        var sf:StackFrame = call_stack[0];
        var safety:int = 255;
        while(sf && safety--) {          
          if(sf.vars.hasOwnProperty(key)) {
            //log('~ in', v);
            sf.vars[key] = value;
            return;
          }
          sf = sf.parent;
        }
        //log('~ in vm globals');
        vm_globals[key] = value; // write to the bottom stack frame's vars; the global dicts are read-only
        //log(Inspector.inspect(call_stack));
        //log(Inspector.inspect(vm_globals));
      };
  
      // TBD: provide a list_vars function to display defined names in system_dicts, vm_globals, and the call_stack
      public function find_var(key:String) : * {
        //log(Inspector.inspect(system_dicts));
        // log(Inspector.inspect(vm_globals));
        var v:* = _find_var(key);
        if(undefined === v) {
          trace('* * * [VM] find_var('+key+') : not found');
          // trace(Inspector.inspect(vm_globals));
          return null;
        }
        
        log(' '+ key + ' -> ', typeof(v), v);
        
        return v;
      }
  
      private function _find_var(key:String) : * {
        // Look for the var in the current function call's scope...
        var sf:StackFrame = call_stack[0];
        var safety:int = 255;
        while(sf && safety--) {          
          if(sf.vars.hasOwnProperty(key)) {
            return sf.vars[key];
          }
          sf = sf.parent;
        }
        
        // ( Could support dynamic scope here by walking the call stack. )
        
        // ... then in the globals
        if(vm_globals.hasOwnProperty(key)) {
          return vm_globals[key];        
        }
        
        // ... then in the system dictionaries ...  (used only by unit tests and to provide the trace and halt functions) 
        for (var i:int=0;i<system_dicts.length; i++) {
          var g:Object = system_dicts[i];
          if(g.hasOwnProperty(key)) {
            return g[key];
          }
        }
        
        // ... and finally, in the registry.       
        if(VM.registry.hasOwnProperty(key)) {
          return VM.registry[key];
        }
        
        // If the var hasn't been found, it's not defined anywhere. 
        return undefined;
      };

    public function next_word() : * {
      return callframe.next_word();
    };
  
/*
**       
**          OPCODES
**
*/
    
        //stack manipulation
        private function DUP()   :void{ var p:* = opop(); opush(p); opush(p); }
        private function DROP()  :void{ opop(); }
        /*private function DROPALL()  :void{ os.length = 0; }
        private function CLEARTOMARK()  :void{ yanktomark(); }*/
        private function SWAP()  :void{ var a:* = opop(); var b  : * = opop(); opush(a); opush(b); }
        private function INDEX() :void{ var index :*= opop(); opush(os[index]); }

        //literal
        private function LIT():void{   var v:* = next_word();  opush(v);  }
        
        //variable
        private function VAL():void{   opush(find_var(next_word())); }

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
            cpush(right, {}); // Creates a callframe/scope.  "a && v = 3" will set v in global scope if not defined in the enclosing scope.
          }
        }
        
        private function AND():void{ 
            _short_circuit_if(false);            
        }

        private function OR():void{ 
          _short_circuit_if(true);            
        }

        private function NOT():void{ 
            opush(!opop());
        }

        //fn defs
        private function CLOSURE():void{ 
            var closure:Function;
            log(Inspector.inspect(os));
            var body:Array= opop();
            var args:Array= opop();
            var name:String = opop();
            log('~~~~CLOSURE', name, '(', args,')', '{', body, '}');
            closure = wrapVmFunc( new VmFunc(name, args, body));
            set_var(name, closure);
            opush(closure);
        }

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
            var prevpc:int = callframe.pc;
            var offset:int = next_word();
            callframe.pc += offset;
            // log('jump', prevpc, '+'+offset, ' -> ', callframe.pc)
        }
        private function JUMPFALSE():void{ 
            var prevpc:int = callframe.pc;
            var offset:int = next_word();
            if(!opop()) {
                callframe.pc += offset;
            }
        }

        
        private function wrapVmFunc(fn:VmFunc):Function{
          var vm:VM = this;
          var enclosingLexicalScope:StackFrame = call_stack[0];

          // the function will be reassigned to anon0 within the VM,
          // but the closure created here will be a new one referencing
          // the current environment in the enclosing function.

          return function(...args):void {
            log('calling wrapped vm func ``' +  fn.name + '\'\' with arguments: ' + Inspector.inspect(args));
            vm.cpush(fn.body, conformArgumentListToVmFuncArgumentHash(args, fn), enclosingLexicalScope);
            if(vm.depth > VM.MAX_RECURSION_DEPTH) { 
              throw new Error('org.sixsided.scripting.SJS.VM: too much recursion in' + fn.name);
            }
            vm.run(); // if called from within SJS code, recurses into VM::run(); if called from an AS callback, starts up the interpreter
          }
        }  
        
        // untested
        private function conformArgumentListToVmFuncArgumentHash(func_args:Array, fn:VmFunc):Object {
          var ret:Object = {};
          for (var i:String in fn.args) {
            var k:String = fn.args[i];
            ret[k] = func_args.shift();
          }
          return ret;
        }

         private function CALL():void{ 
            var func_args:* = opop();
            var fn:* = opop();
             
            if(fn is Function) {
                // TODO -- supply a "this" context for scripted functions?
                // FIXME -- How to distinguish between functions returning nothing and functions
                //          returning undefined? For now, we don't.
                var rslt:* = fn.apply(null, func_args);
                if(rslt !== undefined) opush(rslt); 
                return;
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
          opush(find_var(key));
        }
        
        // v k PUT
        private function PUT():void{  // (value key -- value )
          var key:String = opop();
          var value:* = opop();
          log('PUT', value, key);
          set_var(key, value);
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
          callframe.vars[key] = undefined;
        }
        
        // NEW   ( constructor [args] -- instance )
        private function NATIVE_NEW():void {            
            var args:Array = opop();
            var classname:String = opop();
            var klass:Class = find_var(classname);
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
        
        private function _resumeFromPromise(...ignoredArgs) : void {
          trace('_resumeFromPromise', ignoredArgs);
          run();
        }
        
        private function AWAIT():void {
          var p:Promise = opop();
          halt();
          p.onFulfill(_resumeFromPromise);
        }
            
        private function NOP():void{ 
          //log('nop');
        }
        
        // an opcode is unnecessary; use halt() or add suspend() instead.
        //private function HALT(){
        //  state = STATE_HALTED;
        //}
  
/*    function _prebind_ops(tokens){
      log('prebinding tokens:', tokens);
      for(var i in tokens) {
        var t = tokens[i];
        if(this.hasOwnProperty(t)) {
          tokens[i] = this[t];
        }
      }
      return tokens;
    };
*/    

    } // VM
  
} // package
