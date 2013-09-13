Simplified JavaScript (SJS) is a JavaScript interpreter you can embed in your Flash ActionScript 3 projects.  

SJS is useful as an embedded scripting language for games or an exploratory debugging tool.

Inspirations: 
----------------
Douglas Crockford's "Top Down Operator Precedence"
http://javascript.crockford.com/tdop/tdop.html

Richard W.M. Jones' implementation of FORTH 
http://annexia.org/forth

Features
--------
* can parse and execute most JavaScript.
* can import AS3 objects by calling interpreter.setGlobal("objectNameInJS", objectNameInAS3)
* can instantiate native flash objects like MovieClip with the "new" operator and manipulate them.
* async "await" statement that pauses the VM until a Promise is fulfilled

Omissions
-----------
* prototype chain
* multiple assignment (i.e. a = b = c)
* semicolons are required

Await
-----------

    protected function waitBriefly() : Promise {
        var t:Timer = new Timer(1000, 1);
        var p:Promise = new Promise();
        t.addEventListener(Timer.TIMER, function(e:TimerEvent) { promise.fulfill(23); } )
        t.start();
        return p;
    }
    
    // ... then ....
    myInterpreter.setGlobal('doSomethingAsync', waitBriefly);
    
    myInterpreter.doString(  "trace(1);                         "
                           + "await x = doSomethingAsync();     "
                           + "trace(x);                         " );

    // interpreter will trace out "23" after one second.
    
    


How it works:
=============

SJS operates on JavasScript in four stages:

1) Tokenize the source code.
  Lexer.as breaks the source code into a flat array of tokens like '{', 'while', '=', '!=', etc.
  This is just Douglas Crockford's lexer.

2) Parse the token array.
  Parser.as converts the token array into a tree of parse node objects, such that a preorder traversal
  of the tree, printing each node, would emit an arithemetic expression like 2 + 3 * 4
  in RPN, ie, 2 3 4 * +
  
3) Generate VM opcodes from the parse tree
  Parser.as walks the tree in preorder, calling the codegen method of each parse node, and storing
  the emitted VM opcodes.
  
  The parse tree can be dumped out in a representation that looks like a postfix LISP.
  This input:
    1 + 2 * 3 / 4 % 5
  would appear as:
    (+ 1 (% (/ (* 2 3) 4) 5))
  
4) Execute the opcodes.
  The VM iterates through the opcode array, modifying its own internal state in response to each one.
  It can also instantiate and perform method calls on Flash objects like MovieClip if they've been
  installed in its static member VM.registry:Object
  
  I use short human-readable strings to represent the opcodes, so we can easily read the generated
  code to make sure it's what's expected.
  
  This parse tree:
    (+ 1 (% (/ (* 2 3) 4) 5))
  Would generate this code:
    LIT 1 LIT 2 LIT 3 MUL LIT 4 DIV LIT 5 MOD ADD




Note for RemoteConsole.as:
===========================
		serve policy files on Flash's expected port 843 with netcat:		
			while true ; cat policy.xml | nc -l 843 ; end
			
		listen for connections from the Flash app with:
			rlwrap nc -lk 8080
		
		better yet, run remote-console-hub.py, which provides a "chat" server 
		that stays up across multiple runs of your SWF. Connect to it and issue
		commands from Terminal with:

			rlwrap nc localhost 9000
		
		
		
		
