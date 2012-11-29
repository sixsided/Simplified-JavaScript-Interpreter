/*  Parser

  The class takes the unconventional (for AS3) step of defining a bunch of
  "symbol" objects like this:
  
    { bpow:an_int, nud: function() { ... }, led:function(){ ... }, std:function() { ... } }
  
  Some symbols have only nud, some have only led, some have both, and some have only std. 

  (These are abbreviations for Null Denotation, Left Denotation, and Statement Denotation,
  in the terminology of Pratt parsing.
  
    Let's take the example of:
      y = [1,2,3];
      z = 1;
      x = y[z];
      
    Null Denotation: we call the NUD of '[' on the first line; the resulting token doesn't reference anything to the left of it:
                      { first:[1,2,3] }

    Left Denotation: we call the LED of '[' on the last line; the resulting '[' token slurps in 'y':
                      { first:y, second:z }

    Statement Denotation: a special case for statements like return and var, which don't have a value, as opposed to expressions which do
    
   )
  
  The symbols are all conceptually similar, but there's a lot of variability in the
  nud and led functions, and I didn't want to define 20-odd different classes for
  what's basically a data structure.



      pseudo-types:
        token:    {type, value, from, to}
        symbol:   {nud, led, std, bpow, codegen} associated with an id
    
        parsenode: token + symbol + id
          - could set the prototype of each token to the symbol with the matching id
          - could make a ParseNode class per symbol and construct one instance around each token read
        the id of a parseNode references
  
*/

package org.sixsided.scripting.SJS {
    
  import org.sixsided.util.ANSI;
    
  public class Parser {

      public var symtab:Object = {};
      public var scopes:Array = [[]]; // just names
      public var tokens:Array = [];
      public var token:Object = null;
      public var token_idx:int = 0;
      public var source_code:String;
      public var generated_code:Array = [];

      public var ID_END    :String = '(end)';
      public var ID_LITERAL:String = '(literal)';
      public var ID_NAME   :String = '(name)'; // we attach IDs to lexer tokens
      public var T_NAME    :String = 'name';  // tokens from the lexer have type, value, from, and to

      public var END_TOKEN :Object = {id:ID_END, toString:function():String{return "*END*";}};
       
      public var ast:Object;


      // debug cruft
      public var xd:int = 0 ;
      public var tracing:Boolean = false;



      /***********************************************************
      *
      *    PUBLIC API
      *
      *     opcode = (new Parser()).parse(src).codegen();
      *     opcode = (new Parser()).codegen(src);
      *
      ***********************************************************/
      public function Parser() {
          init_symbols();
      }
      
      // usage:  vm.load ( parser.parse(js_code).codegen()).run();
      // or: interp.load(js); interp.run();
      // or: new Interpreter(js});


        public function parse (src:String):Parser {
            tokens = [];
            token = null;
            token_idx = 0;
            source_code = src;
    
            tokens = Lexer.tokenize(src);
            next();
            ast = statements();
            return this;
        };


        public function codegen(src:String = null):Array{
          if(src) { parse(src); }
          
          log("##### CODE GENERATION ####\n", JSON.stringify(ast));
          
          generated_code = [];
          C(ast);
          log('## GENERATED:', generated_code.join(" "));
          return generated_code;
        };
    


      /***********************************************************
      *
      *    DEBUG 
      *
      ***********************************************************/

      public function dump_node(tree:Object) : String {
           var ret:Array = [];
           
           function p(s:String) : void {
             ret.push(s);
           }
           
           function pval(v:*) : void {
             //p(v.value + ':' + typeof v.value);
             p(v.value);
           }
           

           function dnr(n:*) : void {
               if(!n) return;

               if(n is Array) {
                   p('[');                     // '[' and ']' for arrays, such as argument arrays
                   var i:int = 0;
                   for each (var v:* in n) {
                       dnr(v);
                       if(++i < n.length) { p(','); }
                   }
                   p(']')
               } else if( n.hasOwnProperty('first')){               // '(' and ')' around node children
                   p('(');
                   if(n.value == '(') p('CALL'); else if(n.value == '[') p("ARRAY"); else pval(n);
                   dnr(n.first);
                   dnr(n.second);
                   dnr(n.third);
                   p(')');
               } else {
                   pval(n);
                   return;
               }
           }
           
           dnr(tree);
           return ret.join(' ');
       }        
       
        public function dump_ast():String{
          return dump_node(ast);
        };
    
    
        public function codegen_string():String {
          this.codegen();
          return generated_code.join(' ');
        };

        private function _annotateVarsWithType(e:*, i:int, a:Array) : String {          
          if(i == 0 || a[i-1] != VM.LIT) {
            return e;  // don't annotate non-literals with type
          }
          
          if(e is Array) {
            return "[ " + e.map(_annotateVarsWithType).join(' ') + ' ]'
          }
          
          return typeof(e) + ':' + e;          
          /*return ':' + e;*/
        }
        
        public function dbg_codegen_string():String {
          this.codegen();
          return generated_code.map(_annotateVarsWithType).join(' ');
        };

    
      public function log(... msg) : void {
          if(tracing) {
            var indent:String = '                                    '.slice(0, xd * 4);
            trace(indent, '[Parser]', msg.join(' '));
          }
      }
      
  
    public function formattedSyntaxError(t:Object) : String {
      var nlChar:Object = {"\n":true, "\r":true};
      
      function line_start(pos:int):int {
        while(pos > 0 && !nlChar[source_code.charAt(pos)]) pos--;
        return Math.max(0, pos);
      }
      
      function line_end(pos:int):int {
        var z:int = source_code.length - 1;
        while(pos < z && !nlChar[source_code.charAt(pos)]) pos++;
        return Math.min(z, pos);
      }
      
      var a:int = line_start(line_start(t.from) - 1);
      var z:int = line_end(line_end(t.to) + 1);
      
      const ansi_escape:String = ANSI.RED + ANSI.INVERT;
      var dupe:String = source_code.substring(0, t.from) + ansi_escape + source_code.substring(t.from, t.to) + ANSI.NORMAL + source_code.substring(t.to);
            
      return dupe.substring(a, z+(ansi_escape + ANSI.NORMAL).length);
      
    }
      


      /***********************************************************
      *
      *    PARSER CORE
      *
      ***********************************************************/

      // reserved words stay reserved -- operators

      public function _extend(a:Object, b:Object) : Object { 
        for(var k:String in b) {
          a[k] = b[k];
        } 
        return a;
      }

      public function next(id:String=null) : Object {         
          if(id && token.id != id) {
              log('Parser::next expected to be on "' + id + '" but was on "' + dump_node(token) + '"');
              if(id == ';') throw new Error('missing a semicolon near ' + offending_line(token.from));
              throw new Error('unexpected token, id: `' + token.id + ' value: `' + token.value + "' in next()");
          }
              
          var pt:Object = token;
          token = tokens[token_idx++];
          
          if(token_idx > tokens.length) return token  = END_TOKEN;

          if(token.type == 'name') {
              if(symtab.hasOwnProperty(token.value)) {
                  token.id = token.value;
              } else {
                  token.id = ID_NAME;
              }
          } else if(token.type == 'string' || token.type == 'number') {
              token.id = ID_LITERAL;
              // lexer transforms numbers to floats
          } else /*operator*/ {
              token.id = token.value;
          }
        
          return _extend(token, symtab[token.id]); // clone FTW.  So what if it might be slow?   handles the this binding simply.
      }

    public function infix_codegen(opcode:*):Function { 
      return function():void { 
        C(this.first); 
        C(this.second); 
        emit(opcode); 
      };
    }


    public function infix_thunk_rhs_codegen(opcode:*):Function { 
      return function():void { 
        C(this.first);
        // delay evaluation of second child by wrapping it in an array literal
        emit(VM.LIT);
        emit(codegen_block(this.second));
        emit(opcode);
      };
    }
    

    public function prefix_codegen(opcode:*):Function { 
      return function():void { C(this.first); emit(opcode); };
    }


    public function symbol(sym:String):Object {
      if(!symtab.hasOwnProperty(sym)) symtab[sym] = {};
      return symtab[sym];
    }


    public function infix(sym:String, bpow:Number, opcode:*) : Object {
      
        function leftDenotation(lhs:Object):Object {
          this.first = lhs;
          this.second = expression(this.bpow);
          return this;          
        }
        
          return symtab[sym] = {  led:leftDenotation,
                                  codegen:infix_codegen(opcode),
                                  bpow:bpow };
      };


      public function infix_thunk_rhs(sym:String, bpow:Number, opcode:*) : Object {
            return symtab[sym] = {
                                    led:function(lhs:Object):Object {
                                            this.first = lhs;
                                            this.second = expression(this.bpow);
                                            return this;
                                      },
                                    codegen:infix_thunk_rhs_codegen(opcode),
                                    bpow:bpow
            };
        };


    public function prefix(sym:String, bpow:Number, opcode:*) : void { 
        var s:Object = symbol(sym);
        s.bpow = s.bpow || 140;  // don't want infix - to get a higher precedence than *, for example.
        s.nud = function():Object {
            this.first = expression(0);
            return this;
        };
        s.codegen = prefix_codegen(opcode);
    }


  public function assignment(id:String, bpow:int, operation:String=null) : void {
        var sym:Object = symbol(id);
        sym.bpow = bpow;
      
      
        var mutate:Boolean = operation ? true : false;    // operation is "+" for +=, "-" for -=, etc; and null for "=". 
      
        sym.led = function(lhs:Object):Object {
                                    this.first = lhs;
                                    this.second = expression(this.bpow - 1 );  /* drop the bpow by one to be right-associative */
                                    this.assignment = true;
                                    return this;
                                };

        sym.codegen = function():void {
            if(mutate) {                                    
                // do the operation     // if it's "x += 3", then...
                C(this.first);          // LIT x
                C(this.second);         // VAL 3
                emit(operation);        // ADD
            } else {
                // just emit the value   // if it's "x = 3", then:  LIT 3
                C(this.second);
            }

            //assign it to the lhs
            C(this.first, true);        // LIT x 

            if(this.first.id=='.') {
                // e.g. for "point.x += 3", change the opcode from:
                //    VAL point LIT x GETINDEX LIT 3 ADD    VAL point LIT x GETINDEX
                // to:                                                      ^^^
                //    VAL point LIT x GETINDEX LIT 3 ADD    VAL point LIT x PUTINDEX
                remit(VM.PUTINDEX); // PUTINDEX consumes the stack (val obj key)  and does obj[key] = val;
            } else {
                emit(VM.PUT);
            }
            // PUT leaves the value onstack for multiple assignment, DROP it as we come out of the nested assignments
            // need_drop();
        };

    }


    public function affix(id:String, bpow:int, opcode:String) : void {
       symtab[id] = {
              bpow:bpow,
              isPrefix:false,
              led:function(lhs:Object) : Object {
                this.first = lhs;
                return this;
              },
              nud:function() : Object {
                // next must be variable name
                if(token.id == ID_NAME) {
                  this.first = token;
                  this.isPrefix = true;
                  next();
                  return this;
                } else {
                  throw new Error("Expected ID_NAME after ++ operator");
                }
              },
              codegen:function() : void {
                // increment the variable, leaving a copy of its previous value on the stack.
                if(this.isPrefix) {
                  C(this.first);
                  emit(VM.LIT, 1, opcode); 
                  emit(VM.DUP);
                  C(this.first, true);
                  emit(VM.PUT);
                } else /* postfix */ {
                  C(this.first);
                  emit(VM.DUP);
                  emit(VM.LIT, 1, opcode); 
                  C(this.first, true);
                  emit(VM.PUT);
                }
              }
            };      
    }

       

  
    public function constant(id:String, v:*) : Object {
      return symtab[id] = {
          nud:function():Object{ 
            this.value = v;
            return this;
          },
          bpow:0, 
          codegen:function():void {
                      emit_lit(this.value);
          }
      };
    }


    public function expression(rbp:Number):Object {
          xd++;
          // grab first token and call its nud
          var t:Object = token;
          next();
          if(t.nud == undefined) {
            trace(formattedSyntaxError(t));
            throw new SyntaxError("Unexpected " + t.id + " token:  ``" + t.value + "''" + " at char:" + t.from + "-" + t.to + " || line: " + offending_line(t.from));
          }
          var lhs:Object = t.nud();
          // shovel left hand side into higher-precedence tokens' methods
          while (rbp < token.bpow){
              t = token;
              next();              
              if(!t.led) { 
                throw new SyntaxError(t + 'has no led in ' + source_code);
              }
              lhs = t.led(lhs);
          } 
          xd--;
          return lhs;
      }
                     
    public function block():Object {
      var t:Object = token;
      next("{");
      return t.std();
    };

      
    public function statement():Object{
        var ret:Object, t:Object = token;
        if(t.std) {
            next();
            ret = t.std();
            return ret;
        }

        var xstmt:Object = expression(0);
    
        if(!(xstmt.assignment || xstmt.id == '(')) { 
            throw( new Error('invalid expression statement :' +  offending_line(t.from)) );
        } // neither assignment nor function call
        next(';');
        return xstmt;
    }
          

      public function statements():Array{
          var stmts:Array = [];
          for(;;) {
              if(token.id == '}' || token.id == ID_END) break;
              stmts.push(statement());
          }
          return stmts;
      }     

    /***********************************************************
    *
    *    CODEGEN
    *
    ***********************************************************/

    public function emit1(opcode:*, ...ignore) : void {
      emit(opcode);
    }
    
    public function emit(... opcodes) : void {
      for(var i:int=0; i<opcodes.length;i++){
          generated_code.push(opcodes[i]);
      }
    }

    public function remit(token:Object):void {
      generated_code.pop();
      emit(token);
    }

    public function emit_lit(v:*):void {
      emit('LIT');
      emit(v);
    }

    public function emit_prefix(node:Object, op:*):void {
      C(node); emit(op);
    }
    public function emit_infix(n1:Object, n2:Object, op:*):void {
      C(n1); C(n2); emit(op);
    }

    // usage = j = emit_jump_returning_patcher(VM.JUMPFALSE); ... emit a bunch of stuff ... j();
    // opcodes are:  JUMP|JUMPFALSE <offset>
    // The offset is from the address of JUMPFALSE, not of <offset>
  public function emit_jump_returning_patcher(opcode:*):Function {
      emit(opcode);
      var here:int = generated_code.length;
      function patcher():void { 
        generated_code[here] = generated_code.length - here - 1; // decrement to factor in the <offset> literal
      }
      emit('@patch'); // placeholder @here
      return patcher;
  }
          
          
  public function backjumper(opcode:*):Function {
      // opcodes emitted:  JUMP|JUMPFALSE <offset>
      // currently uses only JUMP, but will need JUMPFALSE to support "do { ... } while(test)" semantics    (TBD)
      var here:int = generated_code.length;
      return function():void { 
        emit(opcode);
        var offset:int = here - generated_code.length - 1; // decrement to factor in the <offset> literal
        emit(offset);
      }
  }
          
    // public var drops_needed:int = 0;                 // fixme: this seems really incorrect.  take multiple assignment out?
    // public function need_drop():void { drops_needed++; }  // see assignment()  ^^^... no, make codegen return and concat arrays recursively
    
    public function C(node:Object, is_lhs:Boolean=false):void {  
      if(!node) {
        trace('empty node reached');
        return;
      }
 
      // TODO: if multiple assignment: MARK .. C ... CLEARTOMARK
      
       if(node is Array) { // statements or argument lists
        for(var i:int=0;i<node.length;i++) {
            C(node[i], is_lhs);
            /*emit(VM.DROPALL);*/
            // we might need to drop some leftover values from a multiple assignment
            // while(drops_needed > 0) { 
            //   log('emitting drop after multiple assignment,', drops_needed, 'remaining');
            //   emit(VM.DROP);
            //   drops_needed--;
            // }
        }
      } else {
        if(!node.hasOwnProperty('codegen')) { 
          throw new SyntaxError('No Codegen for '+node.name+'#'+node.id+'='+node.value);
        } else {
          node.codegen(is_lhs);
        }
      }
    }
    
    
    // for code like " a { b c } d  ", return [a, [b, c], d]
    public function codegen_block(node:Object):*{
      var orig_code:Array = generated_code;
      generated_code = [];
      C(node);
      var block_code:Array = generated_code;
      generated_code = orig_code;
      return block_code;
    }
    

    public function C_hash(o:Object):void{
      for(var k:String in o) {
        emit('LIT', k);
        C(o[k]);
      }
    }


  // scope handling stuff at present only exists to prevent name collisions at parse time.
     public function scope_define(name:String):void {
        // used by: function, var
/*        log('scope_define', name);*/
// allow redefinition so we can say function x() {...} repeatedly during dev
        // for each(var existing_name:String in scopes[0]) {
        //   if(existing_name == name) {
        //     throw new Error('tried to redefine variable ' + existing_name + ' in line "' + offending_line() + '"');
        //   }
        // }
        scopes[0].push(name); // FIXME, throw an error if it's already defined 
      }
      public  function scope_push():void {
        scopes.unshift([]);
      }
      public function scope_pop():void {
        scopes.shift();
      }
      

    public function parse_argument_list():Array {
        var args:Array = [];
        
        if(token.id == ')') return args;  // bail if args list is empty; caller is responsible for consuming )
        
        while(true) {
            args.push(expression(0));
            if(token.id != ',') { // this would be the closing )
                break;
            }
            next(',');
        }
        return args;
    }    
    
    public var getAnonFuncName_id:int = 0;
    public function getAnonFuncName():String {
      return 'anon' + getAnonFuncName_id++;
    }
      
    public function init_symbols():void {

      //constants
      constant('true', true);
      constant('false', false);

      //primitives
      symtab[ID_NAME] = {
          nud:function():Object {return this;},
          toString:function():String {return this.value;},
          codegen:function(am_lhs:Boolean):void {  emit(am_lhs ? 'LIT' : 'VAL',  this.value); }  // need a reference if we're assigning to the var; the value otherwise.
      };

      symtab[ID_LITERAL] = {
          nud:function():Object {return this;},
          toString:function():String{return this.value;},
          bpow:0,
          codegen:function():void { 
            emit_lit(this.value); 
          } // tbd test w/ lexer change to parse numbers
      };
  
      //assignment
      // fixme: and here we see why V K SWAP SET is more consistent than V K PUT
      assignment('=', 20);
      assignment('+=', 130, VM.ADD);
      assignment('-=', 130, VM.SUB);
      assignment('*=', 130, VM.MUL);
      assignment('/=', 130, VM.DIV);
      assignment('%=', 130, VM.MOD);

      affix('++', 140, VM.ADD);
      affix('--', 140, VM.SUB);
            

      prefix('!', 140, VM.NOT);
      infix('+', 120, VM.ADD);
      infix('-', 120, '*minus*');
      prefix('-', 120, '*unary minus*');

      // tbd: different codegens by arity?
      symtab['-'].codegen = function():void { 
          if(this.second) 
          emit_infix(this.first, this.second, VM.SUB);
          else {
              emit_prefix(this.first, VM.NEG);
          }
      };
        

      infix('*', 130, VM.MUL);
      infix('/', 130, VM.DIV);
      infix('%', 130, VM.MOD);


            // comparison
      infix('<', 100, VM.LT);
      infix('<=',100, VM.LTE);
      infix('>', 100, VM.GT);
      infix('>=',100, VM.GTE);
      infix('==', 90, VM.EQL);

  
      infix_thunk_rhs('&&', 50, VM.AND);
      infix_thunk_rhs('||', 40, VM.OR);

      
       infix('.', 160, VM.GETINDEX); // a.b.c indexing operator
       //indexing
       // RHS [k(1) dot... k(n-1) dot] dict k(n) put
       // where dot has stack effect ( o k -- o[k] )
       // a.b.c.d = e -- $ e $a # b dot # c dot # d dot dict 
       symtab['.'].codegen = function(is_lhs:Boolean /* assignment? */):void {
           if(this.first.id != '.') {
               C(this.first, false); // use VAL
           } else {
               C(this.first, true);  // use LIT
           }
           C(this.second, true); // treat as LHS until the last item in the dot-chain
           emit(VM.GETINDEX);
       };
            
            
    symbol('new');
    symbol('new').bpow = 160;
    symbol('new').nud = function():Object {
        if(token.type != T_NAME) throw("Expected name after new operator, got " + token.value + " in: " + offending_line());
        this.first = token;
        next(/*constructor*/);
        next('(');
        this.second = token.id == ')' ? [] : parse_argument_list();
        next(')');
        return this;
    };
    symbol('new').codegen = function():void {
        emit_lit(this.first.value);
        emit(VM.MARK);
        C(this.second);
        emit(VM.ARRAY);
        emit(VM.NATIVE_NEW);   // ( constructor [args] -- instance )
    };
    

            
      symtab['('] = {   
            bpow:160,
            isFunctionCall:false,

            // subexpression
            nud:function():Object{
                var expr:Object = expression(0);
                next(')');
                return expr;
            },
  
            // function call
            led:function(lhs:Object):Object{
                this.first = lhs;
                // will be on '('
                this.second = parse_argument_list();
                next(')');
                this.isFunctionCall = true;
                return this;
            },
        
            codegen:function():void {
              /*// recurse and find "..." async in argument list?
              //whatabout f(..., f2(...))
              // : translates to await f(resumeLastAwait, await f2(resumeLastAwait))
              //
              function isEllipsis(arg:Object, i:int, a:Array):Boolean {
                return arg.id == '...';
              }*/
              
              /*var isAsync:Boolean = this.second.some(isEllipsis);*/

              C(this.first);
              emit(VM.MARK);
              C(this.second);
              emit(VM.ARRAY);
              emit(VM.CALL);

              /*if(this.second.some(isEllipsis)) {
                emit(VM.AWAIT);
              }*/

            }
      };
        
      symtab[')'] = { bpow:-1 };    // ?? fixme


      symtab['function'] = {
        std:function():Object {
            var fn_name:Object = token;
            var args:Array = [];
            next(/* skip the function name */);
      
            if(fn_name.type != T_NAME) { throw("Invalid function name '" + fn_name.value + "' on line: " + offending_line()); }
            
            scope_define(fn_name.value);
            scope_push();
            this.scope = scopes[0];
            next('(');
            if(token.id != ')') {
                args = parse_argument_list();
            }
            next(')');
            next('{');
            var body:Array = statements();
            next('}');
      
            scope_pop();
       
            this.first = fn_name;
            this.second = args;
            this.third = body;
      
      
            return this;
        },
        
       
        nud:function():Object {
          var args:Array = [];
          // we need to create a fake function-name token for this anonymous function
          var fn_name:Object = {
            id: ID_NAME,
            type: T_NAME,
            value: getAnonFuncName(),
            isAnonymous:true
          };

          scope_push();
          this.scope = scopes[0];
          next('(');
          if(token.id != ')') {
              args = parse_argument_list();
          }
  
          next(')');
          next('{');
          var body:Array = statements();
            //trace('function nud:', Inspector.inspect(body));
          next('}');

          scope_pop();

          this.first = fn_name;
          this.second = args;
          this.third = body;

          return this;
        },

        bpow:0,
        
        codegen:function():void {
          /* generates: 
            LIT "function_name"               
            MARK   
              LIT arg1..
              LIT argN
            ARRAY
            -- array of opcodes
            LIT
            [
              LIT local1 LOCAL, ... 
              LIT localN LOCAL 
              ... opcodes ...
            ]
            CLOSURE
            
          */
          
          // currently:
          // function f(a) { var v; trace(v); }  -->  LIT f MARK LIT a LIT v LOCAL ARRAY [ LIT trace MARK LIT v ARRAY CALL ] DEF
          // desired:
          // function f(a) { var v; trace(v); }  -->   <MARKER> LIT f MARK LIT a LIT v LOCAL ARRAY LIT trace MARK LIT v ARRAY CALL ] <CLOSURE>
          
          // function name literal
          emit_lit(this.first.value);
          
          // arguments
          emit(VM.MARK);
          C(this.second, true);
          emit(VM.ARRAY);
          
          // tbd: fix this hack to create locals at the beginning of a function's code block
          var body:Array = codegen_block(this.third);
          for each(var v:* in this.scope) { body.unshift(VM.LOCAL); body.unshift(v); body.unshift(VM.LIT); }

          emit(VM.LIT);
          
          emit(body);
          
          //emit(VM.MARK); emit(VM.EVAL_OFF); body.forEach(emit1); emit(VM.EVAL_ON); emit(VM.ARRAY);  // not the greatest idea
          emit(VM.CLOSURE);
          if(!this.first.isAnonymous) {
            /*trace('emitting drop for named function codegen');*/
            emit(VM.DROP); // anon function will presumably be assigned to something... although, wait, this kills the module pattern: (function(){...})()
          }
        }     
      };

      symtab['return'] = {
          bpow:0,
          std:function():Object {            
              // peek at next token to see if this is "return;" as opposed to "return someValue;"
              if(token.id != ';') {
                this.first = expression(0);
              }
              next(';');
              return this;
          },
          codegen:function():void {
                   C(this.first);
                   emit(VM.RETURN);
              }
      };

      symtab['['] = {      
        
          // x = [1,2,3]
          nud:function():Object {
              var a:Array = [];
              
              if(token.id != ']') {
                for(;;){
                  a.push(expression(0));
                  if(token.id != ',') break;
                  next(',');
                }
              }
              next(']');
              this.first = a;
              
              this.subscripting = false;
              return this;
          },
          
          // x = y[z]
          led:function(lhs:Object):Object{
              this.first = lhs;  // "y"
              // will be on '['
              this.second = expression(0); // "z"
              next(']');

              this.subscripting = true;
              return this;
          },
          
          
          toString:function():String { return "(array " + this.first + ")"; },
          bpow:160,
          codegen:function(is_lhs:Boolean = false):void { 
            if(this.subscripting) {
              //this.first could be a variable name or a literal array, e.g.  [1,2,3][0];  getArray()[0]
              //we want to throw whatever it is on the stack, then getIndex it.
              C(this.first, false); // use VAL, in "x = y[z]", we want the value of y on the stack
              C(this.second, false); // treat as RHS...      // FIXME: a[i] = n fails by using PUTINDEX
              emit(is_lhs ? VM.PUTINDEX : VM.GETINDEX);
            } else {
              emit('MARK'); C(this.first); emit('ARRAY');
            }
          }

      };


      symtab['{'] = { 
         std:function():Object { 
           var a:Array = statements();
           next('}');
           return a;
         }, 
         nud:function():Object {
            var key:Object, value:Object, obj:Object = {};
            for(;;) {
              key = token;
              next();
              next(':');
              value = expression(0);
              obj[key] = value;
              //next(); // --> , or }
              if(token.id != ',') break;
              next();
            }
            next('}');
            this.first = obj;
            return this;
         },
         codegen:function():void { emit('MARK'); C_hash(this.first);  emit('HASH'); }
      };

    /***********************************************************
    *
    *    CONTROL STRUCTURES
    *
    ***********************************************************/


      symtab['if'] = {
          std:function():Object {
              next('(');
              var cond:Object = expression(0);
              next(')');
              next('{');
              var then_block:Array = statements();
              next('}');
              this.first = cond;
              this.second = then_block;
        
              // trace(token);
              if(token.id == ID_NAME && token.value == 'else') {
                next(); // skip else
                var t:Object = token;
                this.third = t.value == 'if' ? statement() : block( /* eats  { and } */);
                // what if the next statement's another if?
              }
              return this;
          },
          bpow:0,

          codegen:function():void {
              C(this.first); // test
          
              var patch_if:Function = emit_jump_returning_patcher(VM.JUMPFALSE);
              C(this.second);
              patch_if();
          
              if(this.third) {
                var patch_else:Function = emit_jump_returning_patcher(VM.JUMP);
                patch_if();
                C(this.third);
                patch_else();  // rewrite @else to point after "if{...}else{...}" instructions.
              }
            }        
      };

      symtab['while'] = {
          std:function():Object {
              next('(');
              var cond:Object = expression(0);
              next(')');
              next('{');
              var block:Array = statements();
              next('}');
              this.first = cond;
              this.second = block;
              return this;
          },
          bpow:0,
          codegen:function():void {
              var emit_backjump_to_test:Function = backjumper(VM.JUMP);
              C(this.first);
              var patch_jump_over_body:Function = emit_jump_returning_patcher(VM.JUMPFALSE);
              C(this.second);
              emit_backjump_to_test();
              patch_jump_over_body();
            }          
      };


      symtab['for'] = {
          std:function():Object {
           // for (initial-expr ; test-expr ; final-expr ) { body }
           next('(');
           var init:Object = expression(0);
           next(';');
           var test:Object = expression(0);
           next(';');
           var modify:Object = expression(0);
           next(')');
           next('{');
           var block:Array = statements();
           next('}');
           this.first = [init,test,modify];
           this.second = block;
           
           return this; // UNTESTED
          },
          bpow:0,
                                                        // "for(i = 0; i < 10; i++) { trace(i); }"
          codegen:function():void{
              C(this.first[0]);                         // i = 0
              var backjump_to_test:Function = backjumper(VM.JUMP);
              C(this.first[1]);                         // i < 10
              var jumpfalse_to_here:Function = emit_jump_returning_patcher(VM.JUMPFALSE);
              C(this.second);                           // trace(i);
              C(this.first[2]);                         // i ++
              backjump_to_test();                       // } --> JUMP to i < 10
              jumpfalse_to_here();                      // patch the JUMPFALSE after "i<10" 
          }
      };


      symtab['var'] = {
          std:function():Object {
/*            trace('* var statement');*/
              var e:Object, names:Array = [];
              for(;;){
                  e = expression(0);
                  if(e.id != '=' && e.id != ID_NAME) { 
                      throw new Error('Unexpected intializer ' + e + ' in var statement :' + offending_line(this.from));
                  }
                  names.push(e);
                  // here's one place where static typing would have saved me trouble:
/*                  scope_define(e.id == 'NAME' ? e.id : e.first.id)*/
                  scope_define(e.type == T_NAME ? e.value : e.first.value);

                  if(token.id != ',') break;
                  next(',');
              }
              next(';');
              this.first = names;
/*              trace('* --- end var statement');*/
              return this;
          },
          bpow:0,
          toString:function():String {
              return '(var '+ this.first + ')';
          },
          codegen:function():void{            
            /*            trace("var codegen doesn't do anything; it's just a marker.");*/
            /* TODO: codegen should prefix locals with LOCAL opcode(TBD) */
            C(this.first, true);
          }
      };
      
      /*
        await fn();
        doSomething(x(), await y());      
      */
        
      symtab['await'] = {
        // isStatement flag exists so we can clear the stack after statements like
        // "await promiseReturnsSomeValues();"
        // but not in expressions like 
        // "myArray = promiseReturnsSomeValues();"
        
        isStatement : false, 
        
        expectFunctionCall:function():void {
            if(!this.first.isFunctionCall) throw "Expected function call after await";
        },
        
        std:function():Object {
          this.isStatement = true;
          this.first = statement();
          this.expectFunctionCall();
          return this;
        },
        
        nud:function():Object {
          this.first = expression(0);
          this.expectFunctionCall();
          return this;
        },
        
        codegen:function():void {
          if(this.isStatement) emit(VM.MARK)
          C(this.first);  // There should be an async method call somewhere in this subtree, 
                          // which will leave a Promise on the stack.
                         
          emit(VM.AWAIT); // AWAIT will then consume the Promise; its fulfillment will resume the VM
                          // with one value on the stack.
                          // if (this.first) consumed it, fine; in case it hasn't, clear to the mark:
                          
          if(this.isStatement) emit(VM.CLEARTOMARK);
        }
      }


            
    }

     // return the text of the source-code line containing a given character offset (which offset we originally got from the lexer)
     public function offending_line(near:int=-1):String {
       var line_start:int, line_end:int;
       var nlChar:Object = {"\n":true, "\r":true};
       if(near<0) near = token.from;
       // back up to the start of the line
       for(line_start = near; line_start >= 0 && !nlChar[source_code.charAt(line_start)]; line_start--)
          /* ok */ true;
       // walk forward to the end of the line
       for(line_end = near; line_end < source_code.length && !nlChar[source_code.charAt(line_end)]; line_end++)
          /* ok */ true;
       return source_code.substring(line_start,line_end);
     }


  } // class        
}
