package  org.sixsided.scripting.SJS {
	
	public class ANSI {
    public static var ESC:String = "\x1B["; //String.fromCharCode(27) + '['; 

    public static var NORMAL: String = "\x1B[1;0m";    // 0  NORMAL

    public static var BLACK  : String = "\x1B[1;30m";  // 30  BLACK
    public static var RED    : String = "\x1B[1;31m";  // 31  RED
    public static var GREEN  : String = "\x1B[1;32m";  // 32  GREEN
    public static var YELLOW : String = "\x1B[1;33m";  // 33  YELLOW
    public static var BLUE   : String = "\x1B[1;34m";  // 34  BLUE
    public static var MAGENTA: String = "\x1B[1;35m";  // 35  MAGENTA
    public static var CYAN   : String = "\x1B[1;36m";  // 36  CYAN
    public static var WHITE  : String = "\x1B[1;37m";  // 37  WHITE

    public static var BG_BLACK  : String = "\x1B[1;40m";  // 30  BLACK
    public static var BG_RED    : String = "\x1B[1;41m";  // 31  RED
    public static var BG_GREEN  : String = "\x1B[1;42m";  // 32  GREEN
    public static var BG_YELLOW : String = "\x1B[1;43m";  // 33  YELLOW
    public static var BG_BLUE   : String = "\x1B[1;44m";  // 34  BLUE
    public static var BG_MAGENTA: String = "\x1B[1;45m";  // 35  MAGENTA
    public static var BG_CYAN   : String = "\x1B[1;46m";  // 36  CYAN
    public static var BG_WHITE  : String = "\x1B[1;47m";  // 37  WHITE

    public static var UNDERLINE    : String = "\x1B[4m";  // 31  RED
    public static var INVERT    : String = "\x1B[7m";  // 31  RED

    public static var SAVE_CURSOR    : String = "\x1B[s";  // 31  RED
    public static var RESTORE_CURSOR    : String = "\x1B[u";  // 31  RED
	  
	  public static function wrap(fmt:String, ...rest) : String {
	    return fmt + rest.join(' ') + ANSI.NORMAL;
	    
      /*return ANSI.SAVE_CURSOR + fmt + rest.join(' ') + ANSI.NORMAL + ANSI.RESTORE_CURSOR; // TBD */
    }
    
    public function back(n:int) : String {
      // FIXME
      return ANSI.ESC + n + 'D';
    }
    
    public static function error(s:String) : String {
      return ANSI.wrap(ANSI.BG_RED + ANSI.WHITE, s);
    }
    
    public static function green(s:String) : String {
      return ANSI.wrap(ANSI.GREEN, s);
    }
    
    public static function red(s:String) : String {
      return ANSI.wrap(ANSI.RED, s);
    }
    public static function cyan(s:String) : String {
      return ANSI.wrap(ANSI.CYAN, s);
    }
    
	}
}