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
  
*/

package org.sixsided.scripting.SJS {
//    import org.sixsided.scripting.SJS.Inspector;
    
    /*
      pseudo-types:
        token:    {type, value, from, to}
        symbol:   {nud, led, std, bpow, codegen} associated with an id
    
        parsenode: token + symbol + id
          - could set the prototype of each token to the symbol with the matching id
          - could make a ParseNode class per symbol and construct one instance around each token read
        the id of a parseNode references
        
    */
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
            // trace('"""', src, '"""');
            tokens = [];
            token = null;
            token_idx = 0;
            source_code = src;
            
//symtab = {};
//scopes = [[]]; // just names
//tokens = [];
//token = null;
//token_idx = 0;
//source_code = src;
    
            tokens = Lexer.tokenize(src);
            //try {
                next();
                ast = statements();
            //} catch(e) {
            //  
            //}
            return this;
        };




      /***********************************************************
      *
      *    DEBUG CRUFT
      *
      ***********************************************************/
    
        // Traverse the parse tree in preorder and output it in a 
        // postfix notation with lisp-like parenthesization
        public function dump_node(tree:Object) : String {
            var depth:int = 0;
            function pad():String {
              return "\n" + '                                    '.slice(0, depth * 2);
            }

            function dnr(n:*):String {
                if(!n) return '';
                                
                var ret:String = '';
                if(n is Array) {
                  
                    if(n.length == 0) { return pad() + '[]'; } // display empty arrays compactly
                    
                    ret += pad() + '[';                     // '[' and ']' for arrays, such as argument arrays
                    depth++;
                    var i:int = 0;
                    for each (var v:* in n) {
                        ret += dnr(v);
                        if(++i < n.length) { ret += ','; }
                    }
                    depth--;
                    ret += pad() + ']'
                } else if( n.first ){               // '(' and ')' for node children
                    ret = pad() + '(';
                    depth++;
                    ret +=  n.value == '(' ? '@CALL' : n.value;
                    ret += dnr(n.first);
                    ret += dnr(n.second);
                    ret += dnr(n.third);
                    depth--;
                    ret += pad() + ')';
                } else {
                    return pad() + "'" + n.value + "'";
                }
                return ret;
            }
            return dnr(tree);
        }
        
        public function dump_ast():String{
          return dump_node(ast);
        };
    
    
      public function log(... msg) : void {
          if(tracing) {
            var indent:String = '                                    '.slice(0, xd * 4);
            trace(indent, msg.join(' '));
          }
      }


      public function _symbol_tostring():String {
        return "(" + this + ")";
      }


      /***********************************************************
      *
      *    PARSER CORE
      *
      ***********************************************************/



    //                          reserved words stay reserved -- operators
      

      public function _extend(a:Object, b:Object) : Object { 
        for(var k:String in b) {
          a[k] = b[k];
        } 
        return a;
      }

      public function next(id:String=null) : Object {         
        
/*          var nt = tokens[token_idx];
          if(token) log( (id ? '[' + id + '] ' : '') + '"' + token.value + '" --> ' + (nt ? ('"' + nt.value + '"') : ''));
*/    
          if(id && token.id != id) {
              log('Parser::next expected to be on "' + id + '" but was on "' + dump_node(token) + '"');
              if(id == ';') throw new Error('missing a semicolon before ' + offending_line(token.from));
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
              // log('name parsed:', token.id, token.value);

          } else if(token.type == 'string' || token.type == 'number') {
              token.id = ID_LITERAL;
              // lexer transforms numbers to floats
          } else /*operator*/ {
              token.id = token.value;
              // log('op parsed:', token.id);
          }
        
          return _extend(token, symtab[token.id]); // clone FTW.  So what if it might be slow?   handles the this binding simply.
      }


    public function symbol(sym:String):Object {
      if(symtab.hasOwnProperty(sym)) return symtab[sym];
      return symtab[sym] = {}
    }
    
    public function infix(sym:String, bpow:Number, opcode:*) : Object {
      
        function leftDenotation(lhs:Object):Object {
          this.first = lhs;
          this.second = expression(this.bpow);
          return this;          
        }
        
          return symtab[sym] = {
                                  led:leftDenotation,
                                  bpow:bpow
          };
      };


    // TBD: let a script function say  parser.user_infix('x', 160, newPoint);   p = 30 x 60;  function newPoint(a,b) { return new Point(a,b); }
    //public function user_infix(sym:String, bpow:Number, callback:VmFunc) {
    //  return symtab[sym] = {
    //    led:infix_led,
    //    bpow:bpow,
    //    codegen:
    //      function(){
    //        // 23 @ 42  -> VAL newPoint [ 23 42 ] CALL
    //        emit(VM.VAL);
    //        emit_lit(this.id);
    //        emit(VM.MARK);
    //        C(this.first);
    //        C(this.second);
    //        emit(VM.ARRAY);
    //        emit(VM.CALL)
    //      }      
    //}

    public function prefix(sym:String, bpow:Number, opcode:*) : void { 
        var s:Object = symbol(sym);
        s.bpow = s.bpow || 140;  // don't want infix - to get a higher precedence than *, for example.
        s.nud = function():Object {
            this.first = expression(0);
            return this;
        };
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

       
    }

       

  
    public function constant(id:String, v:*) : Object {
            return symtab[id] = {
                nud:function():Object{ 
                  this.value = v;
                  return this;
                },
                bpow:0               
            };
      };


    public function expression(rbp:Number):Object {
          xd++;
          // grab first token and call its nud
          // log('expression(', rbp, ')  // ', dump_node(token), '...');
          var t:Object = token;
          next();
          if(t.nud == undefined) {
            throw new SyntaxError("Unexpected " + t.id + " token:  ``" + t.value + "''" + " at char:" + t.from + "-" + t.to + " || line: " + offending_line(t.from));
          }
          var lhs:Object = t.nud();
          // log('"' + dump_node(t) + '".nud() => ' + lhs);
          // shovel left hand side into higher-precedence tokens' methods
          while (rbp < token.bpow){
              t = token;
              next();
              
              // log('"' + dump_node(t) + '".led(' + dump_node(lhs) + ') -> ');
              if(!t.led) { 
                throw new SyntaxError(t + 'has no led in ' + source_code);
              }
              lhs = t.led(lhs);
              //log('  ' + dump_node(lhs));
              
          } 
          // log('=> ' + dump_node(lhs));
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
              // log('std ' + t);
              ret = t.std();
              // log('-> ' + t);
              return ret;
          }
          // log('no std; expression...');
          var xstmt:Object = expression(0);
          // log(xstmt);
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

/* 
Note: it might be worth storing the symbol table as an {id:symbol} hash
if I decide to put vars on the stack rather than in hash tables, b/c the symbol
could store the var's stack index.  maybe?

    Might be worth investigation for a speed bump later.  AS3 hash lookups are fast,
    but I might eliminate the hashes entirely and throw everything on the stack.  Meh.
*/

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
        // log('parse_argument_list (' + token.value +')');
        var args:Array = [];
        
        if(token.id == ')') return args;  // bail if args list is empty; caller is responsible for consuming )
        
        while(true) {
            args.push(expression(0));
            if(token.id != ',') { // this would be the closing )
                break;
            }
            next(',');
        }
        // log('arguments list:', dump_node(args));
        return args;
    }    
    
    public var getAnonFuncName_id:int = 0;
    public function getAnonFuncName():String {
      return 'anon' + getAnonFuncName_id++;
    }
      
    public function init_symbols():void {

/*    In js, could dump parse tree with:
    Array.prototype.toString = function(){ return "[" + this.join(',') + "]"; };
        Function.prototype.toString = function() { return "*CODE*"; }
    No go in AS3.
*/
      
      //constants
      constant('true', true);
      constant('false', false);

      //primitives
      symtab[ID_NAME] = {
          nud:function():Object {return this;},
          toString:function():String {return this.value;}          
      };

      symtab[ID_LITERAL] = {
          nud:function():Object {return this;},
          toString:function():String{return this.value;},
          bpow:0
      };
  
      //assignment
      // fixme: and here we see why V K SWAP SET is more consistent than V K PUT
      assignment('=', 20);
      assignment('+=', 130, VM.ADD);
      assignment('-=', 130, VM.SUB);
      assignment('*=', 130, VM.MUL);
      assignment('/=', 130, VM.DIV);
      assignment('%=', 130, VM.MOD);

      prefix('!', 140, VM.NOT);
      infix('+', 120, VM.ADD);
      infix('-', 120, '*minus*');
      prefix('-', 120, '*unary minus*');

      // tbd: different codegens by arity?

      infix('*', 130, VM.MUL);
      infix('/', 130, VM.DIV);
      infix('%', 130, VM.MOD);


            // comparison
      infix('<', 100, VM.LT);
      infix('<=',100, VM.LTE);
      infix('>', 100, VM.GT);
      infix('>=',100, VM.GTE);
      infix('==', 90, VM.EQL);

  
      infix_thunk_second('&&', 50, VM.AND);
      infix_thunk_second('||', 40, VM.OR);

      
       infix('.', 160, VM.GETINDEX); // a.b.c indexing operator
      
            
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

            
      symtab['('] = {   
            bpow:160,

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
                return this;
            }      };
        
      symtab[')'] = { bpow:-1 };    // ?? fixme


      symtab['function'] = {
        std:function():Object {
            var fn_name:Object = token;
            var args:Array = [];
            next(/*name*/);       // <-- this is correct
      
            if(fn_name.type != T_NAME) { throw("Invalid function name '" + fn_name.value + "' on line: " + offending_line()); }
            
            scope_define(fn_name.value);
            scope_push();
            this.scope = scopes[0];
            next('(');
            if(token.id != ')') {
                args = parse_argument_list();
/*                for(;;) {
                    log(token);
                    if(token.type != T_NAME) throw new Error('unexpected ' + token.id + ' in fn args');
                    args.push(token);
                    next();
                    if(token.id != ',') break;
                    next();
                }
*/            }
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
          // we need to create a fake function-name token
          var fn_name:Object = {
            id: ID_NAME,
            type: T_NAME,
            value: getAnonFuncName(),
            isAnonymous:true
          };

            //trace('function nud:', Inspector.inspect(token));
          //scope_define(fn_name);
          scope_push();
          this.scope = scopes[0];
          next('(');
            //trace('function nud after next (:', Inspector.inspect(token));
          log('function symbol skipped past (, on token:', token);
          if(token.id != ')') {
              args = parse_argument_list();
          }
            //trace('function nud:', Inspector.inspect(args));
  
          next(')');
          next('{');
          var body:Array = statements();
            //trace('function nud:', Inspector.inspect(body));
          next('}');

          scope_pop();

          this.first = fn_name;
          this.second = args;
          this.third = body;
  
            //trace('function nud 1,2,3:', this.first, this.second, this.third);

          return this;
  
        },

        bpow:0
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
          }
      };

      symtab['['] = {      
        
          // x = [1,2,3]
          nud:function():Object {
              var a:Array = [];
              for(;;){
                  a.push(expression(0));
                  if(token.id != ',') break;
                  next(',');
              }
              next(']');
              this.first = a;
              
              this.subscripting = false;
              return this;
          },
          
          // x = y[z]
          led:function(lhs:Object):Object{
              log('* * * [.led');
            
              this.first = lhs;  // "y"
              // will be on '['
              this.second = expression(0); // "z"
              next(']');

              this.subscripting = true;
              return this;
          },
          
          toString:function():String { return "(array " + this.first + ")"; },
          bpow:160
      };

                           //symtab['.'].codegen = function(is_lhs:Boolean /* assignment? */):void {
                           //               // log('.', this.first.value, this.second.value, is_lhs ? 'LHS' : 'RHS');
                           //               if(this.first.id != '.') {
                           //                   C(this.first, false); // use VAL
                           //               } else {
                           //                   C(this.first, true);  // use LIT
                           //               }
                           //               C(this.second, true); // treat as LHS until the last item in the dot-chain
                           //               log('# emit ' + VM.GETINDEX);
                           //               emit(VM.GETINDEX);
                           //           };
                           //                                           






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
         }
      };
        
            // control structures

        
            //functions



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
                this.third = t.value == 'if' ? statement() : block(/*eats initial { */);
                //next('}'); // block also eats closing }
                // what if the next statement's another if?
              }
              return this;
          },
          bpow:0
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
          bpow:0 
      };


      symtab['for'] = {
          std:function():Object {
           // for (initial-expr ; test-expr ; repeat-expr ) { body }
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
          bpow:0
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
          }
      };



            
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
