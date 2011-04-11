﻿/*  VM	Execute the compiled bytecode.  Inspired heavily by JonesFORTH, to a lesser degree by Postscript and HotRuby.See:  http://replay.waybackmachine.org/20090209211708/http://www.annexia.org/forthNotes to self:  The Array class is one of the few core classes that is not final, which  means that you can create your own subclass of Array. Hmmm.... probably a bad idea.*/package org.sixsided.scripting {  import org.sixsided.util.Inspector;  import flash.utils.getDefinitionByName;  import flash.utils.getQualifiedClassName;   import flash.geom.*;  import flash.display.*;  public class VM {/***       **      ERRORS***/    //   ACCESSED_UNDECLARED_VAR    //   CALLED_NONFUNCTION_VALUE       /***       **      OPCODES***/      public static const NOP:String         = 'NOP';      public static const DUP:String         = 'DUP';      public static const DROP:String        = 'DROP';      public static const SWAP:String        = 'SWAP';      public static const INDEX:String       = 'INDEX';      public static const LIT:String         = 'LIT';      public static const VAL:String         = 'VAL';      public static const ADD:String         = 'ADD';      public static const SUB:String         = 'SUB';      public static const MUL:String         = 'MUL';      public static const DIV:String         = 'DIV';      public static const MOD:String         = 'MOD';      public static const NEG:String         = 'NEG';      public static const EQL:String         = 'EQL';      public static const GT:String          = 'GT';      public static const LT:String          = 'LT';      public static const GTE:String         = 'GTE';      public static const LTE:String         = 'LTE';      public static const AND:String         = 'AND';      public static const OR:String          = 'OR';      public static const NOT:String         = 'NOT';      public static const DEF:String         = 'DEF';      public static const MARK:String        = 'MARK';      public static const ARRAY:String       = 'ARRAY';      public static const HASH:String        = 'HASH';      public static const JUMP:String        = 'JUMP';      public static const JUMPFALSE:String   = 'JUMPFALSE';      public static const CALL:String        = 'CALL';      public static const RETURN:String      = 'RETURN';/*    public static const TRACE:String       = 'TRACE';*/      public static const PUT:String         = 'PUT';      public static const PUTINDEX:String    = 'PUTINDEX';      public static const GETINDEX:String    = 'GETINDEX';      public static const GET:String         = 'GET';      public static const LOCAL:String       = 'LOCAL';      public static const NATIVE_NEW:String  = 'NATIVE_NEW';      //public static const HALT:String        = 'HALT';/***          STATES*/                                public static const STATE_HALTED:String        = 'HALTED';      public static const STATE_RUNNING:String        = 'RUNNING';/***       **          STATIC VARS, METHODS***/    protected static var registry:Object = {}; // for importing Tweener, etc.   formerly 'uber_globals'    public static var dbg_last_vm:VM;          // debugging hack    public static function register(key:String, value:*) {      trace('VM::register(',key,', ', value, ')');      VM.registry[key] = value;    }    static function dbg_dump_os(){      return Inspector.inspect(VM.dbg_last_vm.os);    };                 /***********************************************************  *  *    INSTANCE VARS, GETTERS -- VM STATE  *  ***********************************************************/     // VM state     public var state:String = VM.STATE_RUNNING;     // opcodes     public var code:Array = [];         // function call stack         public var callStack:Array = []; // of StackFrame          // operand stack (like in an RPN calculator)     public var os:Array = [];     // stack indices for array / hash construction     public var marks:Array = [];           // HACK, system dictionaries to allow the VM to operate in the context of another object     // such as a MovieClip, etc. So you can write "x += 10" and the containing MC will move 10 pixels right.     public var system_dicts:Array = [];  /* public so InterpreterHarness can jam stuff into it */     public var vm_globals:Object = {};     // recursion limit     public static const MAX_RECURSION_DEPTH = 64;     public var depth:Number = 0;          // FIXED: save_globals was a hack to persist globals between runs, since "globals" are stored in the root     // StackFrame, which is popped off when a run completes.     // Wanted to make it more js-ish by having a _globals object,     // but this was superceded by vm_globals and improved find_var / set_var     //public var save_globals:Object=null;    private function get callframe():StackFrame { return callStack[0]; }      /************************************************************  **  **        TEST / DEBUG SUPPORT  **  ************************************************************/        public var dbg_traces:Array = []; // read this out in your tests.    public function inject_globals(o:Object) {      // !!! for testing; it'll overwrite existing globals etc      for(var k in o) vm_globals[k] = o[k];      /*      trace('injected globals with ', Inspector.inspect(o), ' yielding: ', Inspector.inspect(system_dicts));*/    };    public function set_global(k:String, v) {      vm_globals[k] = v;    }      /***********************************************************  *  *   PUBLIC API  *  ***********************************************************/    public function VM() {        VM.dbg_last_vm = this;        // FIXME: trace should probably be injected from the test suite -- this may be useful for debugging, though.        // Will need a listener or something for getting at the traces.        var self:VM = this;        system_dicts = [{  'trace':function()  {                              trace('[ VM trace ] ', arguments);                              dbg_traces.push(arguments[0]);                            },                                                    'halt':function(){                              self.halt();                            }}];              }    public function pushdict(dict:Object) {      system_dicts.push(dict);    }        public function load_opcode_string(code:String) {      // for debugging, testing      return this.load(code.split(' '));    };    // can say vm.load(one_liner).run() with no trouble    public function load(tokens) {      //trace('vm.load:'); trace(tokens);              if(typeof(tokens) == 'string') return this.load_opcode_string(tokens);        callStack = [ new StackFrame(tokens, {}) ]; // TBD: replaced save_globals with {}, verify that this works with "var x" statements in one-liners        // optimization idea: callStack = [ new StackFrame(this._prebind_ops(tokens), {}) ];        //trace('VM Load: [' + tokens.join(' ') + ']');        return this;    };        public function do_string(script:String):VM {      load(new Parser().codegen(script));      run();      return this;    }        public static function createAndBoot(script:String, itsGlobals:Object=null) {      var vm:VM = new VM();            trace('createAndBoot', script);            if(itsGlobals) vm.inject_globals(itsGlobals);            vm.do_string(script);            return vm;    }      public function log(...args){      return;      trace(args);    }          public function halt() {      log('~~halt at ', callStack[0].pc);      state = VM.STATE_HALTED;    }    public function run() {      var e:Error;      var cs:Array = callStack;      state = VM.STATE_RUNNING; // HALT operator can stop it.  Just call vm.run() to resume;      try {         while(cs.length) {          while(!cs[0].exhausted) {                        // bail if halted            if(state != VM.STATE_RUNNING) return this;                        var cf:StackFrame = cs[0]; // stash it in case next_word exhausts it, causing it to pop off at the end of this while loop            var w:String = cf.next_word(); // an only legally be String, an opcode            log('@', cf.pc, ' ', w)            var op:Function = this[w];            if(cs[0].exhausted && !(op)) { // extra parentheses to quiet Flash's "function where object expected" warning               /* happens when if..else jumps to the end */               log('exhausted callframe in the middle of the run loop --  ', cs[0].code.join(' '));               continue;            }                    if(!(op)) {              throw new Error('VM got unknown operator ``' + w ); // + "'' in [" + cs[0].code.join(',') + ']');                          }            op();          }          //save_globals = cf.vars; // *** superceded by vm_globals and improved find/set var          cpop();        }      } catch(e) {        throw ("VM caught exception on word `" + w + "`: ``" + e + "'' at #" + callframe.pc + '(' + callframe.code[callframe.pc] + ') of [' + callframe.code.join(' ') + ']' + "\n Trace:\n" + e.getStackTrace());      }      log('    VM Finished run. os: ', '[' + os.join(', ') + ']', ' dicts: ', Inspector.inspect(system_dicts), 'traces:', Inspector.inspect(dbg_traces), "\n");      return this;    };                      // debug          // function get os () {          //   return os;          // };          //           // function get callStack() {          //   return callStack;          // };          //           // function get dbg_traces() {          //   return dbg_traces;          // };          // function get dbgLastCallframe() {          //   return dbgLastCallframe;          // }                /******************************************************              INTERNALS*****************************************************/            // callstack manipulation    function cpush(code:Array,vars:Object) {       depth++;       callStack.unshift(new StackFrame(code,vars));     };    function cpop() {       depth--;       callStack.shift();     };// stack manipulation    public function opush(op) { os.unshift(op); };    public function opop() { return os.shift(); };    public function numpop() { return parseFloat(opop()); };    public function bin_ops() { return [opop(), opop() ].reverse(); };    public function pushmark() { marks.unshift(os.length); };    public function yanktomark(){ return os.splice(0, os.length - Number(marks.shift())).reverse();  }; // fixme: hack, ditch shift-stacks for push-stacks    // var manipulation      /*    find_var/set_var       *  VM has four tiers of variables.       *  1) the curent call frame's vars       *  2) the VM's globals, vm_globals       *  3) the system dicts, in the order they were added -- READ ONLY; set_var does not even look at these       *  4) the VM's static registry, VM.registry       *         *  *** The only writable vars are the current callframe's and the vm globals       *  *** ... that is, locals and globals for a given VM.  Just like Javascript.       *  ....... Could add a 'register' function for adding things to the registry.       */       // so running in the root scope, the 'var' keyword indicates a temporary variable tha won't persist after       // the callstack is exhausted, i.e. the code runs through to its end and the vm exits.       // simply setting a variable with x = n, however, will create a persistent global x.      public function set_var(key:String, value:*) {        log('~~~~ set_var', key, 'to: ``'+value +"''");        for(var i in callStack) {          var v = callStack[i].vars          if(v.hasOwnProperty(key)) {            log('~~~~~~ in', v);            v[key] = value;            return;          }        }        log('~~~~~~ in vm globals');        vm_globals[key] = value; // write to the bottom stack frame's vars; the global dicts are read-only        log(Inspector.inspect(callStack));        log(Inspector.inspect(vm_globals));      };        public function find_var(key:String) {        log('??? find_var "'+ key + '"');        log(Inspector.inspect(system_dicts));        log(Inspector.inspect(vm_globals));        var v:* = _find_var(key);        log('     found:', typeof(v), v);        if(undefined == v) trace('* * * * * VM.find_var('+key+') returned undefined value.  Typo? * * * * * *');        return v;      }        private function _find_var(key:String) {        // Look for the var in the current function call's scope...        var v:Object;        if(callStack.length) {  // if we were invoked by callScriptFunction, we won't have a callStack          v = callStack[0].vars;          if(v.hasOwnProperty(key)) return v[key];        }                // ( Could support upvalues here by walking the call stack. )                // ... then in the globals        if(vm_globals.hasOwnProperty(key)) return vm_globals[key];                        // ... then in the system dictionaries ...  (used only by unit tests and to provide the trace and halt functions)         for (var i:int=0;i<system_dicts.length; i++) {          var g:Object = system_dicts[i];          if(g.hasOwnProperty(key)) return g[key];        }                // ... and finally, in the registry.               if(VM.registry.hasOwnProperty(key)) return VM.registry[key];                // If the var hasn't been found, it's not defined anywhere.         log('??? ' + key + ' not found');        return undefined;      };    public function next_word() {      return callframe.next_word();    };  /***       **          OPCODES***/            //stack manipulation        private function DUP()   { var p = opop(); opush(p); opush(p); }        private function DROP()  { opop(); }        private function SWAP()  { var a = opop(); var b = opop(); opush(a); opush(b); }        private function INDEX() { var index = opop(); opush(os[index]); }        //literal        private function LIT(){   var v:* = next_word();  log('literal', v); opush(v);  }        private function VAL(){   opush(find_var(next_word())); }        //arithmetic        private function ADD(){      var o:Array = bin_ops(); opush(o[0] + o[1]); }        private function SUB(){      var o:Array = bin_ops(); opush(o[0] - o[1]);}        private function MUL(){      var o:Array = bin_ops(); opush(o[0] * o[1]); }        private function DIV(){      var o:Array = bin_ops(); opush(o[0] / o[1]); }        private function MOD(){      var modulus:Number = numpop(); opush(numpop() % modulus); }         private function NEG(){      opush(-opop()); }        //relational        private function EQL(){ opush(opop() == opop());                      }        private function GT() { var o:Array = bin_ops(); opush(o[0] > o[1]);  }        private function LT() { var o:Array = bin_ops(); opush(o[0] < o[1]);  }        private function GTE(){ var o:Array = bin_ops(); opush(o[0] >= o[1]); }        private function LTE(){ var o:Array = bin_ops(); opush(o[0] <= o[1]); }        //logic -- unlike standard js,  a() && b()  will call both functions;  same for a() || b().        private function AND(){             var right = opop();            var left = opop();             opush(left ? right : left);        }        private function OR(){             var right = opop();            var left = opop();             opush( left ? left : right);        }        private function NOT(){            opush(!opop());        }        //fn defs        private function DEF(){          log(Inspector.inspect(os));            var body = opop();            var args = opop();            var name = opop();            log('~~~~DEF', name, '(', args,')', '{', body, '}');            set_var(name, new VmFunc(name, args, body));        }      //structures        private function MARK(){ pushmark(); }        private function ARRAY(){ opush(yanktomark()); }        private function HASH(){              var i:int, dict:Object = {}, a:Array = yanktomark();               for(i=0; i < a.length; i+=2) {                dict[a[i]] = a[i+1];              }              opush(dict);        }              //flow control        private function JUMP(){            var prevpc = callframe.pc;            var offset = next_word();            callframe.pc += offset;            // log('jump', prevpc, '+'+offset, ' -> ', callframe.pc)        }        private function JUMPFALSE(){            var prevpc = callframe.pc;            var offset = next_word();            if(!opop()) {                callframe.pc += offset;            }        }        public function callScriptFunction(funcName:String, args:Array=null) {          var fn:VmFunc = find_var(funcName);          if(!args) args = [];          cpush(fn.body, conformArgumentListToVmFuncArgumentHash(args, fn));          run();        }                // untested        private function conformArgumentListToVmFuncArgumentHash(func_args:Array, fn:VmFunc):Object {          var ret:Object = {};          for (var i in fn.args) {            var k = fn.args[i];            ret[k] = func_args.shift();          }          return ret;        }         private function CALL(){            var func_args = opop();            var fn = opop();            log('calling', typeof(fn), fn, func_args);            if(fn is Function) {                opush(fn.apply(null, func_args)); // fixme -- probably want to call the function in the context of its parent object                return;            } else if (fn is VmFunc) {              log('call user', fn, func_args);              var args_passed = conformArgumentListToVmFuncArgumentHash(func_args, fn);              cpush(fn.body, args_passed);                          if(depth > VM.MAX_RECURSION_DEPTH) {                 throw new Error('too much recursion');              }              log(depth, 'calling', fn.name, 'with', Inspector.inspect(args_passed));            } else {              trace('* * * * * VM.CALL tried to call nonfunction value "' + fn + '": ' + typeof(fn) + ' * * * * * *');            }         }         private function RETURN(){           log('return');           cpop();         }               // getting and setting values                private function GET () {          var key = opop();              opush(find_var(key));        }                private function PUT(){          var key = opop();          var value = opop();          log('PUT', value, key);          set_var(key, value);          opush(value);        }                private function PUTINDEX(){ // ( value object key -- value )          var key = opop();          var object = opop();          var value = opop();          object[key] = value;          opush(value);        }                private function GETINDEX(){ // aka "dot"  (o k -- o[k])            var k = opop();            var o = opop();            opush(o[k]);        }                // LIT m LOCAL -- declares m as a var in current scope        private function LOCAL () {          var key = opop();              callframe.vars[key] = undefined;        }                // NEW   ( constructor [args] -- instance )        private function NATIVE_NEW() {                        var args:Array = opop();            var classname:String = opop();            var klass:Class = find_var(classname);            var instance:*;            log('++ new ', classname, '(' + args.join(', ') + ')  //', klass + ': ' + getQualifiedClassName(klass));                        switch(args.length) {              case 0: instance = new klass(); break;               case 1: instance = new klass(args[0]); break;               case 2: instance = new klass(args[0], args[1]); break;               case 3: instance = new klass(args[0], args[1], args[2]); break;               case 4: instance = new klass(args[0], args[1], args[2], args[3]); break;               case 5: instance = new klass(args[0], args[1], args[2], args[3], args[4]); break;               case 6: instance = new klass(args[0], args[1], args[2], args[3], args[4], args[5]); break;              case 7: instance = new klass(args[0], args[1], args[2], args[3], args[4], args[5], args[6]); break;              case 8: instance = new klass(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]); break;              case 9: instance = new klass(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8]); break;              default: throw "NATIVE_NEW was given too many arguments: " + args.length;            }                   opush(instance);                    }                    private function NOP(){          //log('nop');        }                // an opcode is unnecessary; use halt() or add suspend() instead.        //private function HALT(){        //  state = STATE_HALTED;        //}  /*    function _prebind_ops(tokens){      log('prebinding tokens:', tokens);      for(var i in tokens) {        var t = tokens[i];        if(this.hasOwnProperty(t)) {          tokens[i] = this[t];        }      }      return tokens;    };*/        } // VM  } // package