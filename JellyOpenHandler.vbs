Option Explicit

Const adTypeBinary = 1
Const adTypeText = 2

Dim shell, fso
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

If WScript.Arguments.Count = 1 Then
    If LCase(WScript.Arguments(0)) = "--selftest" Then
        WScript.Quit 0
    End If
End If

If WScript.Arguments.Count < 1 Then
    Fail "No jellyopen URL was supplied."
End If

Dim uri, data, fileManager, mediaPath
uri = WScript.Arguments(0)

data = GetQueryParam(uri, "data")
If Len(data) = 0 Then
    Fail "No encoded media path was supplied."
End If

fileManager = LCase(GetQueryParam(uri, "fm"))
If Len(fileManager) = 0 Then fileManager = "auto"

If fileManager <> "auto" And fileManager <> "dopus" And fileManager <> "explorer" Then
    fileManager = "auto"
End If

On Error Resume Next
mediaPath = DecodeBase64UrlUtf8(data)
If Err.Number <> 0 Then
    Dim decodeErr
    decodeErr = Err.Description
    Err.Clear
    On Error GoTo 0
    Fail "Could not decode the Jellyfin media path." & vbCrLf & vbCrLf & decodeErr
End If
On Error GoTo 0

mediaPath = Trim(mediaPath)
If Len(mediaPath) >= 2 Then
    If Left(mediaPath, 1) = """" And Right(mediaPath, 1) = """" Then
        mediaPath = Mid(mediaPath, 2, Len(mediaPath) - 2)
    End If
End If

If Not IsAbsoluteWindowsPath(mediaPath) Then
    Fail "Refusing a non-Windows path:" & vbCrLf & vbCrLf & mediaPath
End If

Dim isFile, isFolder
isFile = fso.FileExists(mediaPath)
isFolder = fso.FolderExists(mediaPath)

If Not isFile And Not isFolder Then
    Fail "The path reported by Jellyfin does not exist on this PC:" & vbCrLf & vbCrLf & mediaPath
End If

Dim dopusRT
dopusRT = ""

If fileManager <> "explorer" Then
    dopusRT = FindDOpusRT()
End If

If fileManager = "dopus" And Len(dopusRT) = 0 Then
    Fail "Directory Opus was requested in the userscript, but DOpusRT.exe could not be found."
End If

If Len(dopusRT) > 0 And fileManager <> "explorer" Then
    OpenInDOpus dopusRT, mediaPath, isFolder
Else
    OpenInExplorer mediaPath, isFolder
End If

WScript.Quit 0

Sub OpenInDOpus(ByVal dopusRTPath, ByVal targetPath, ByVal targetIsFolder)
    Dim cmd, parentPath, fileName, i, rc

    If targetIsFolder Then
        cmd = Q(dopusRTPath) & " /acmd Go " & Q(targetPath)
        rc = shell.Run(cmd, 0, False)
        Exit Sub
    End If

    parentPath = fso.GetParentFolderName(targetPath)
    fileName = fso.GetFileName(targetPath)

    If Len(parentPath) = 0 Or Len(fileName) = 0 Then
        Fail "Could not split the media path into a parent folder and filename:" & vbCrLf & vbCrLf & targetPath
    End If

    cmd = Q(dopusRTPath) & " /acmd Go " & Q(parentPath)
    rc = shell.Run(cmd, 0, True)

    WScript.Sleep 250

    For i = 1 To 4
        cmd = Q(dopusRTPath) & _
              " /acmd Select " & Q(fileName) & _
              " EXACT DESELECTNOMATCH MAKEVISIBLE"
        rc = shell.Run(cmd, 0, True)

        If i < 4 Then WScript.Sleep 250
    Next
End Sub

Sub OpenInExplorer(ByVal targetPath, ByVal targetIsFolder)
    Dim cmd

    If targetIsFolder Then
        cmd = "explorer.exe " & Q(targetPath)
    Else
        cmd = "explorer.exe /select," & Q(targetPath)
    End If

    shell.Run cmd, 1, False
End Sub

Function FindDOpusRT()
    Dim p, dopusExe, rt

    p = shell.ExpandEnvironmentStrings("%ProgramFiles%") & "\GPSoftware\Directory Opus\DOpusRT.exe"
    If InStr(p, "%ProgramFiles%") = 0 Then
        If fso.FileExists(p) Then
            FindDOpusRT = p
            Exit Function
        End If
    End If

    p = shell.ExpandEnvironmentStrings("%ProgramFiles(x86)%") & "\GPSoftware\Directory Opus\DOpusRT.exe"
    If InStr(p, "%ProgramFiles(x86)%") = 0 Then
        If fso.FileExists(p) Then
            FindDOpusRT = p
            Exit Function
        End If
    End If

    dopusExe = ReadRegString("HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\dopus.exe\")
    If Len(dopusExe) > 0 Then
        rt = fso.BuildPath(fso.GetParentFolderName(dopusExe), "DOpusRT.exe")
        If fso.FileExists(rt) Then
            FindDOpusRT = rt
            Exit Function
        End If
    End If

    dopusExe = ReadRegString("HKLM\Software\Microsoft\Windows\CurrentVersion\App Paths\dopus.exe\")
    If Len(dopusExe) > 0 Then
        rt = fso.BuildPath(fso.GetParentFolderName(dopusExe), "DOpusRT.exe")
        If fso.FileExists(rt) Then
            FindDOpusRT = rt
            Exit Function
        End If
    End If

    dopusExe = ReadRegString("HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\dopus.exe\")
    If Len(dopusExe) > 0 Then
        rt = fso.BuildPath(fso.GetParentFolderName(dopusExe), "DOpusRT.exe")
        If fso.FileExists(rt) Then
            FindDOpusRT = rt
            Exit Function
        End If
    End If

    FindDOpusRT = ""
End Function

Function ReadRegString(ByVal keyPath)
    On Error Resume Next
    Dim value
    value = shell.RegRead(keyPath)

    If Err.Number <> 0 Then
        Err.Clear
        value = ""
    End If

    On Error GoTo 0
    ReadRegString = value
End Function

Function IsAbsoluteWindowsPath(ByVal value)
    Dim re
    Set re = New RegExp
    re.Pattern = "^([A-Za-z]:\\|\\\\)"
    re.IgnoreCase = True
    re.Global = False

    IsAbsoluteWindowsPath = re.Test(value)
End Function

Function GetQueryParam(ByVal url, ByVal wantedName)
    Dim qPos, query, parts, part, eqPos, key, value

    GetQueryParam = ""

    qPos = InStr(url, "?")
    If qPos = 0 Then Exit Function

    query = Mid(url, qPos + 1)
    parts = Split(query, "&")

    For Each part In parts
        eqPos = InStr(part, "=")

        If eqPos > 0 Then
            key = Left(part, eqPos - 1)
            value = Mid(part, eqPos + 1)

            If LCase(key) = LCase(wantedName) Then
                GetQueryParam = value
                Exit Function
            End If
        End If
    Next
End Function

Function DecodeBase64UrlUtf8(ByVal value)
    Dim b64, padLen, xml, node, bytes, stream, text

    b64 = Replace(value, "-", "+")
    b64 = Replace(b64, "_", "/")

    padLen = Len(b64) Mod 4
    If padLen > 0 Then
        b64 = b64 & String(4 - padLen, "=")
    End If

    Set xml = CreateObject("Msxml2.DOMDocument.6.0")
    Set node = xml.createElement("base64")
    node.DataType = "bin.base64"
    node.Text = b64
    bytes = node.nodeTypedValue

    Set stream = CreateObject("ADODB.Stream")
    stream.Type = adTypeBinary
    stream.Open
    stream.Write bytes
    stream.Position = 0
    stream.Type = adTypeText
    stream.Charset = "utf-8"

    text = stream.ReadText
    stream.Close

    If Len(text) > 0 Then
        If AscW(Left(text, 1)) = &HFEFF Then
            text = Mid(text, 2)
        End If
    End If

    DecodeBase64UrlUtf8 = text
End Function

Function Q(ByVal value)
    Q = """" & value & """"
End Function

Sub Fail(ByVal message)
    MsgBox message, vbCritical + vbOKOnly, "Jellyfin - Open file location"
    WScript.Quit 1
End Sub
