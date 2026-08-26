' The string functions, and the edges where they clamp rather than fail.
DEFINT A-Z
DIM s AS STRING
s = "hello"
PRINT LEN(s)
PRINT LEFT$(s, 3); "|"; LEFT$(s, 99); "|"; LEFT$(s, 0); "|"
PRINT RIGHT$(s, 3); "|"; RIGHT$(s, 99); "|"; RIGHT$(s, 0); "|"
PRINT MID$(s, 2); "|"; MID$(s, 9); "|"
PRINT MID$(s, 2, 3); "|"; MID$(s, 4, 99); "|"
PRINT INSTR(s, "ll"); INSTR(s, "zz"); INSTR(3, "abcabc", "a")
PRINT UCASE$("MiXeD"); "|"; LCASE$("MiXeD")
PRINT "|"; LTRIM$("   pad   "); "|"; RTRIM$("   pad   "); "|"
PRINT ASC("A"); "|"; CHR$(66)
PRINT "|"; SPACE$(4); "|"; STRING$(5, "*"); "|"
PRINT "con" + "cat"
END
