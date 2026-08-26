' Every supplied function, once each, with the edges that need clamping.
PRINT "ABS   "; ABS(-4.5); " "; ABS(-7)
PRINT "SGN   "; SGN(-9); " "; SGN(0); " "; SGN(3)
PRINT "INT   "; INT(2.7); " "; INT(-2.5)
PRINT "FIX   "; FIX(2.7); " "; FIX(-2.5)
PRINT "SQR   "; SQR(16)
PRINT "EXPLOG"; EXP(0); " "; LOG(1)
PRINT "TRIG  "; SIN(0); " "; COS(0); " "; TAN(0); " "; ATN(0)
PRINT "LEN   "; LEN("hello")
PRINT "LEFT  "; LEFT$("hello", 3); "|"; LEFT$("hi", 10); "|"; LEFT$("hi", 0); "|"
PRINT "RIGHT "; RIGHT$("hello", 3); "|"; RIGHT$("hi", 10); "|"; RIGHT$("hi", 0); "|"
PRINT "MID2  "; MID$("hello", 3); "|"; MID$("hello", 9); "|"
PRINT "MID3  "; MID$("hello", 2, 3); "|"; MID$("hello", 4, 99); "|"
PRINT "INSTR "; INSTR("hello", "ll"); " "; INSTR("hello", "zz"); " "; INSTR(3, "abcabc", "a")
PRINT "CASE  "; UCASE$("MiXeD"); " "; LCASE$("MiXeD")
PRINT "TRIM  |"; LTRIM$("   pad   "); "|"; RTRIM$("   pad   "); "|"
PRINT "ASCCHR"; ASC("A"); " "; CHR$(66)
PRINT "STR   |"; STR$(42); "|"
PRINT "VAL   "; VAL("3.5") + 1
PRINT "SPACE |"; SPACE$(4); "|"
PRINT "STRING|"; STRING$(5, "*"); "|"
RANDOMIZE 1
r = RND
IF r >= 0 AND r < 1 THEN PRINT "RND    in range"
END
