package org.sixsided.scripting.SJS {

  // tokens.js
  // 2007-08-05
  // Can't beat Douglas Crockford's js lexer, so what follows is an almost-unmodified copy of it:
  

  // (c) 2006 Douglas Crockford

  // Produce an array of simple token objects from a string.
  // A simple token object contains these members:
  //      type: 'name', 'string', 'number', 'operator'
  //      value: string value of the token
  //      from: index of first character of the token
  //      to: index of the last character + 1

  // Comments of the // type are ignored.

  // Operators are by default single characters. Multicharacter
  // operators can be made by supplying a string of prefix and
  // suffix characters.
  // characters. For example,
  //      '<>+-&', '=>&:'
  // will match any of these:
  //      <=  >>  >>>  <>  >=  +: -: &: &&: &&

  public class Lexer {
  

    public static function tokenize(src:String, prefix:String='=<>!+-*&|/%^', suffix:String='=<>&|+-'):Array {
        var c:*;                      // The current character.
        var from:int;                   // The index of the start of the token.
        var i:int = 0;                  // The index of the current character.
        var length:int = src.length;
        var n:*;                      // The number value.
        var q:String;                      // The quote character.
        var str:String;                    // The string value.

        var result:Array = [];            // An array to hold the results.
    
        var make:Function = function (type:String, value:*):Object {

    // Make a token object.
            if(type == 'number') value = parseFloat(value);
            return {
                type: type,
                value: value,
                from: from,
                to: i,
                error:function(msg:String):void { throw(msg); }
            };
        };

    // Begin tokenization. If the source string is empty, return nothing.

        if (!src) {
            return null;
        }

/*    // If prefix and suffix strings are not provided, supply defaults.

        if (typeof prefix !== 'string') {
            prefix = '=<>!+-*&|/%^';
        }
        if (typeof suffix !== 'string') {
            suffix = '=<>&|';
        }
*/
    // Loop through src text, one character at a time.

        c = src.charAt(i);
        while (c) {
            from = i;

    // Ignore whitespace.

            if (c <= ' ') {
                i += 1;
                c = src.charAt(i);

    // name.

            } else if (c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c === '_') {
                str = c;
                i += 1;
                for (;;) {
                    c = src.charAt(i);
                    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                            (c >= '0' && c <= '9') || c === '_') {
                        str += c;
                        i += 1;
                    } else {
                        break;
                    }
                }
                result.push(make('name', str));

    // number.

    // A number cannot start with a decimal point. It must start with a digit,
    // possibly '0'.

            } else if (c >= '0' && c <= '9') {
                str = c;
                i += 1;

    // Look for more digits.
    
                // hex number?
                if(src.charAt(i) == 'x') {
                    str = '';
                    i += 1;

                    for (;;) {
                        c = src.charAt(i);
                        if ((c < '0' || c > '9') && (c < 'a' || c > 'f') && (c < 'A' || c > 'F')) {
                            break;
                        }
                        i += 1;
                        str += c;
                    }
                    n = parseInt(str, 16);
                    if (isFinite(n)) {
                        result.push(make('number', n));
                    } else {
                        make('number', str).error("Bad hex number");
                    }
                } else {
                    //regular number
                
                    for (;;) {
                        c = src.charAt(i);
                        if (c < '0' || c > '9') {
                            break;
                        }
                        i += 1;
                        str += c;
                    }

        // Look for a decimal fraction part.

                    if (c === '.') {
                        i += 1;
                        str += c;
                        for (;;) {
                            c = src.charAt(i);                        
                            if (c < '0' || c > '9') {
                                break;
                            }
                            i += 1;
                            str += c;
                        }
                    }

        // Look for an exponent part.

                    if (c === 'e' || c === 'E') {
                        i += 1;
                        str += c;
                        c = src.charAt(i);
                        if (c === '-' || c === '+') {
                            i += 1;
                            str += c;
                        }
                        if (c < '0' || c > '9') {
                            make('number', str).error("Bad exponent");
                        }
                        do {
                            i += 1;
                            str += c;
                            c = src.charAt(i);
                        } while (c >= '0' && c <= '9');
                    }

        // Make sure the next character is not a letter.

                    if (c >= 'a' && c <= 'z') {
                        str += c;
                        i += 1;
                        make('number', str).error("Bad number");
                    }

        // Convert the string value to a number. If it is finite, then it is a good
        // token.

                    n = parseFloat(str);  // was +str
                    if (isFinite(n)) {
                        result.push(make('number', n));
                    } else {
                        make('number', str).error("Bad number");
                    }
                } // hex / regular number

    // string

            } else if (c === '\'' || c === '"') {
                str = '';
                q = c;
                i += 1;
                for (;;) {
                    c = src.charAt(i);
                    if (c < ' ') {
                        make('string', str).error(c === '\n' || c === '\r' || c === '' ?
                            "Unterminated string." :
                            "Control character in string.", make('', str));
                    }

    // Look for the closing quote.

                    if (c === q) {
                        break;
                    }

    // Look for escapement.

                    if (c === '\\') {
                        i += 1;
                        if (i >= length) {
                            make('string', str).error("Unterminated string");
                        }
                        c = src.charAt(i);
                        switch (c) {
                        case 'b':
                            c = '\b';
                            break;
                        case 'f':
                            c = '\f';
                            break;
                        case 'n':
                            c = '\n';
                            break;
                        case 'r':
                            c = '\r';
                            break;
                        case 't':
                            c = '\t';
                            break;
                        case 'u':
                            if (i >= length) {
                                make('string', str).error("Unterminated string");
                            }
                            c = parseInt(src.substr(i + 1, 4), 16);
                            if (!isFinite(c) || c < 0) {
                                make('string', str).error("Unterminated string");
                            }
                            c = String.fromCharCode(c);
                            i += 4;
                            break;
                        }
                    }
                    str += c;
                    i += 1;
                }
                i += 1;
                result.push(make('string', str));
                c = src.charAt(i);

    // comment.

            } else if (c === '/' && src.charAt(i + 1) === '/') {
                i += 1;
                for (;;) {
                    c = src.charAt(i);
                    if (c === '\n' || c === '\r' || c === '') {
                        break;
                    }
                    i += 1;
                }

    // combining

            } else if (prefix.indexOf(c) >= 0) {
                str = c;
                i += 1;
                while (i < length) {
                    c = src.charAt(i);
                    if (suffix.indexOf(c) < 0) {
                        break;
                    }
                    str += c;
                    i += 1;
                }
                result.push(make('operator', str));

    // single-character operator

            } else {
                i += 1;
                result.push(make('operator', c));
                c = src.charAt(i);
            }
        }
        return result;
    }

  }

}