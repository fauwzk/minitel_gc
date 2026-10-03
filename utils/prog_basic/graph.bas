10 PRINT "Graphique"
20 X = 0
30 Y = 0
40 FOR I = 1 TO 23
50   x = x + i
60   y = 2 * i + 1
70   IF y > 23 THEN y = 1
80   IF x > 80 THEN x = 1
100   LOCATE X, Y
110   PRINT "*"
120 NEXT I

