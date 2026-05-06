Set Shell = CreateObject("WScript.Shell")

If WScript.Arguments.Count = 0 Then
  WScript.Quit 1
End If

Command = ""
For I = 0 To WScript.Arguments.Count - 1
  Part = WScript.Arguments(I)
  If InStr(Part, " ") > 0 Then
    Part = Chr(34) & Part & Chr(34)
  End If

  If Command = "" Then
    Command = Part
  Else
    Command = Command & " " & Part
  End If
Next

Shell.Run Command, 0, False
