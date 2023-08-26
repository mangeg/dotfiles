using namespace System.Management.Automation
using namespace System.Management.Automation.Language

[console]::InputEncoding = [console]::OutputEncoding = [Text.Encoding]::UTF8
$env:LC_ALL='C.UTF-8'

if (-not (Test-Path Env:\OMP_THEME)) {
    Write-Error "OMP_THEME environment variable does not exist."
    Write-Error "Configure OMP_THEME to a valid oh-my-posh theme file."
    return;
}

oh-my-posh --init --shell pwsh --config $env:OMP_THEME | Invoke-Expression
$env:POSH_GIT_ENABLED = $true

Import-Module -Name PSReadLine
Import-Module -Name Terminal-Icons
Import-Module -Name CompletionPredictor
Import-Module -Name posh-git


# PS ReadLine config
Set-PSReadLineOption -PredictionSource HistoryAndPlugin
Set-PSReadLineOption -PredictionViewStyle ListView

Set-PSReadLineKeyHandler -Key Ctrl+UpArrow -Function PreviousHistory
Set-PSReadLineKeyHandler -Key Ctrl+DownArrow -Function NextHistory
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# Aliases
New-Alias which get-command
New-Alias g git
New-Alias e explorer
New-Alias k kubectl
New-Alias d docker
New-Alias t terraform

# Windows Terminal
## Split horizontal
Set-PSReadLineKeyHandler -Key Ctrl+Alt+s `
                         -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("wt -w 0 sp -d .")
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()                       
}
## Split vertical
Set-PSReadLineKeyHandler -Key Ctrl+Alt+Shift+s `
                         -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("wt -w 0 sp -H -d .")
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()                       
}
## Split 
Set-PSReadLineKeyHandler -Key Ctrl+shift+s `
                         -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("wt -w 0 nt -d .")
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()                       
}

# CaptureScreen is good for blog posts or email showing a transaction
# of what you did when asking for help or demonstrating a technique.
Set-PSReadLineKeyHandler -Chord 'Ctrl+d,Ctrl+c' -Function CaptureScreen

# Dev
Set-PSReadLineKeyHandler -Key Ctrl+Shift+b `
                         -BriefDescription BuildCurrentDirectory `
                         -LongDescription "Build the current directory" `
                         -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("dotnet build")
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadLineKeyHandler -Key Ctrl+Shift+t `
                         -BriefDescription BuildAndTestCurrentDirectory `
                         -LongDescription "Runt test in the current directory" `
                         -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("dotnet test")
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadLineKeyHandler -Key Ctrl+Alt+c `
                         -BriefDescription StartCodeCurrentDirectory `
                         -LongDescription "Starts VS Code in current directory" `
                         -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("code .")
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

## PowerShell parameter completion shim for the dotnet CLI
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
     param($commandName, $wordToComplete, $cursorPosition)
         dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
         }
 }

 ## dotnet suggest shell start
if (Get-Command "dotnet-suggest" -errorAction SilentlyContinue)
{
    $availableToComplete = (dotnet-suggest list) | Out-String
    $availableToCompleteArray = $availableToComplete.Split([Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries)

    Register-ArgumentCompleter -Native -CommandName $availableToCompleteArray -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $fullpath = (Get-Command $commandAst.CommandElements[0]).Source

        $arguments = $commandAst.Extent.ToString().Replace('"', '\"')
        dotnet-suggest get -e $fullpath --position $cursorPosition -- "$arguments" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }    
}
else
{
    "Unable to provide System.CommandLine tab completion support unless the [dotnet-suggest] tool is first installed."
    "See the following for tool installation: https://www.nuget.org/packages/dotnet-suggest"
}

$env:DOTNET_SUGGEST_SCRIPT_VERSION = "1.0.2"

# PowerShell parameter completion shim for winget CLI
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
        $Local:word = $wordToComplete.Replace('"', '""')
        $Local:ast = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

#region Smart Insert/Delete

# The next four key handlers are designed to make entering matched quotes
# parens, and braces a nicer experience.  I'd like to include functions
# in the module that do this, but this implementation still isn't as smart
# as ReSharper, so I'm just providing it as a sample.

Set-PSReadLineKeyHandler -Key '"',"'" `
                         -BriefDescription SmartInsertQuote `
                         -LongDescription "Insert paired quotes if not already on a quote" `
                         -ScriptBlock {
    param($key, $arg)

    $quote = $key.KeyChar

    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    # If text is selected, just quote it without any smarts
    if ($selectionStart -ne -1)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $quote + $line.SubString($selectionStart, $selectionLength) + $quote)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        return
    }

    $ast = $null
    $tokens = $null
    $parseErrors = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$null)

    function FindToken
    {
        param($tokens, $cursor)

        foreach ($token in $tokens)
        {
            if ($cursor -lt $token.Extent.StartOffset) { continue }
            if ($cursor -lt $token.Extent.EndOffset) {
                $result = $token
                $token = $token -as [StringExpandableToken]
                if ($token) {
                    $nested = FindToken $token.NestedTokens $cursor
                    if ($nested) { $result = $nested }
                }

                return $result
            }
        }
        return $null
    }

    $token = FindToken $tokens $cursor

    # If we're on or inside a **quoted** string token (so not generic), we need to be smarter
    if ($token -is [StringToken] -and $token.Kind -ne [TokenKind]::Generic) {
        # If we're at the start of the string, assume we're inserting a new string
        if ($token.Extent.StartOffset -eq $cursor) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote ")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            return
        }

        # If we're at the end of the string, move over the closing quote if present.
        if ($token.Extent.EndOffset -eq ($cursor + 1) -and $line[$cursor] -eq $quote) {
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            return
        }
    }

    if ($null -eq $token -or
        $token.Kind -eq [TokenKind]::RParen -or $token.Kind -eq [TokenKind]::RCurly -or $token.Kind -eq [TokenKind]::RBracket) {
        if ($line[0..$cursor].Where{$_ -eq $quote}.Count % 2 -eq 1) {
            # Odd number of quotes before the cursor, insert a single quote
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
        }
        else {
            # Insert matching quotes, move cursor to be in between the quotes
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
        return
    }

    # If cursor is at the start of a token, enclose it in quotes.
    if ($token.Extent.StartOffset -eq $cursor) {
        if ($token.Kind -eq [TokenKind]::Generic -or $token.Kind -eq [TokenKind]::Identifier -or 
            $token.Kind -eq [TokenKind]::Variable -or $token.TokenFlags.hasFlag([TokenFlags]::Keyword)) {
            $end = $token.Extent.EndOffset
            $len = $end - $cursor
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor, $len, $quote + $line.SubString($cursor, $len) + $quote)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($end + 2)
            return
        }
    }

    # We failed to be smart, so just insert a single quote
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
}

Set-PSReadLineKeyHandler -Key '(','{','[' `
                         -BriefDescription InsertPairedBraces `
                         -LongDescription "Insert matching braces" `
                         -ScriptBlock {
    param($key, $arg)

    $closeChar = switch ($key.KeyChar)
    {
        <#case#> '(' { [char]')'; break }
        <#case#> '{' { [char]'}'; break }
        <#case#> '[' { [char]']'; break }
    }

    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    
    if ($selectionStart -ne -1)
    {
      # Text is selected, wrap it in brackets
      [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar)
      [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    } else {
      # No text is selected, insert a pair
      [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
      [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
}

Set-PSReadLineKeyHandler -Key ')',']','}' `
                         -BriefDescription SmartCloseBraces `
                         -LongDescription "Insert closing brace or skip" `
                         -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($line[$cursor] -eq $key.KeyChar)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
    else
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
    }
}

Set-PSReadLineKeyHandler -Key Backspace `
                         -BriefDescription SmartBackspace `
                         -LongDescription "Delete previous character or matching quotes/parens/braces" `
                         -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($cursor -gt 0)
    {
        $toMatch = $null
        if ($cursor -lt $line.Length)
        {
            switch ($line[$cursor])
            {
                <#case#> '"' { $toMatch = '"'; break }
                <#case#> "'" { $toMatch = "'"; break }
                <#case#> ')' { $toMatch = '('; break }
                <#case#> ']' { $toMatch = '['; break }
                <#case#> '}' { $toMatch = '{'; break }
            }
        }

        if ($toMatch -ne $null -and $line[$cursor-1] -eq $toMatch)
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
        }
        else
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
        }
    }
}

# Sometimes you want to get a property of invoke a member on what you've entered so far
# but you need parens to do that.  This binding will help by putting parens around the current selection,
# or if nothing is selected, the whole line.
Set-PSReadLineKeyHandler -Key 'Alt+(' `
                         -BriefDescription ParenthesizeSelection `
                         -LongDescription "Put parenthesis around the selection or entire line and move the cursor to after the closing parenthesis" `
                         -ScriptBlock {
    param($key, $arg)

    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($selectionStart -ne -1)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, '(' + $line.SubString($selectionStart, $selectionLength) + ')')
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    }
    else
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, '(' + $line + ')')
        [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
    }
}

# Each time you press Alt+', this key handler will change the token
# under or before the cursor.  It will cycle through single quotes, double quotes, or
# no quotes each time it is invoked.
Set-PSReadLineKeyHandler -Key "Alt+'" `
                         -BriefDescription ToggleQuoteArgument `
                         -LongDescription "Toggle quotes on the argument under the cursor" `
                         -ScriptBlock {
    param($key, $arg)

    $ast = $null
    $tokens = $null
    $errors = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

    $tokenToChange = $null
    foreach ($token in $tokens)
    {
        $extent = $token.Extent
        if ($extent.StartOffset -le $cursor -and $extent.EndOffset -ge $cursor)
        {
            $tokenToChange = $token

            # If the cursor is at the end (it's really 1 past the end) of the previous token,
            # we only want to change the previous token if there is no token under the cursor
            if ($extent.EndOffset -eq $cursor -and $foreach.MoveNext())
            {
                $nextToken = $foreach.Current
                if ($nextToken.Extent.StartOffset -eq $cursor)
                {
                    $tokenToChange = $nextToken
                }
            }
            break
        }
    }

    if ($tokenToChange -ne $null)
    {
        $extent = $tokenToChange.Extent
        $tokenText = $extent.Text
        if ($tokenText[0] -eq '"' -and $tokenText[-1] -eq '"')
        {
            # Switch to no quotes
            $replacement = $tokenText.Substring(1, $tokenText.Length - 2)
        }
        elseif ($tokenText[0] -eq "'" -and $tokenText[-1] -eq "'")
        {
            # Switch to double quotes
            $replacement = '"' + $tokenText.Substring(1, $tokenText.Length - 2) + '"'
        }
        else
        {
            # Add single quotes
            $replacement = "'" + $tokenText + "'"
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
            $extent.StartOffset,
            $tokenText.Length,
            $replacement)
    }
}

# This example will replace any aliases on the command line with the resolved commands.
Set-PSReadLineKeyHandler -Key "Alt+%" `
                         -BriefDescription ExpandAliases `
                         -LongDescription "Replace all aliases with the full command" `
                         -ScriptBlock {
    param($key, $arg)

    $ast = $null
    $tokens = $null
    $errors = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

    $startAdjustment = 0
    foreach ($token in $tokens)
    {
        if ($token.TokenFlags -band [TokenFlags]::CommandName)
        {
            $alias = $ExecutionContext.InvokeCommand.GetCommand($token.Extent.Text, 'Alias')
            if ($alias -ne $null)
            {
                $resolvedCommand = $alias.ResolvedCommandName
                if ($resolvedCommand -ne $null)
                {
                    $extent = $token.Extent
                    $length = $extent.EndOffset - $extent.StartOffset
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                        $extent.StartOffset + $startAdjustment,
                        $length,
                        $resolvedCommand)

                    # Our copy of the tokens won't have been updated, so we need to
                    # adjust by the difference in length
                    $startAdjustment += ($resolvedCommand.Length - $length)
                }
            }
        }
    }
}

# Insert text from the clipboard as a here string
Set-PSReadLineKeyHandler -Key Ctrl+Shift+v `
                         -BriefDescription PasteAsHereString `
                         -LongDescription "Paste the clipboard text as a here string" `
                         -ScriptBlock {
    param($key, $arg)

    Add-Type -Assembly PresentationCore
    if ([System.Windows.Clipboard]::ContainsText())
    {
        # Get clipboard text - remove trailing spaces, convert \r\n to \n, and remove the final \n.
        $text = ([System.Windows.Clipboard]::GetText() -replace "\p{Zs}*`r?`n","`n").TrimEnd()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("@'`n$text`n'@")
    }
    else
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Ding()
    }
}

#
# Ctrl+Shift+j then type a key to mark the current directory.
# Ctrj+j then the same key will change back to that directory without
# needing to type cd and won't change the command line.

#
$global:PSReadLineMarks = @{}

Set-PSReadLineKeyHandler -Key Ctrl+J `
                         -BriefDescription MarkDirectory `
                         -LongDescription "Mark the current directory" `
                         -ScriptBlock {
    param($key, $arg)

    $key = [Console]::ReadKey($true)
    $global:PSReadLineMarks[$key.KeyChar] = $pwd
}

Set-PSReadLineKeyHandler -Key Ctrl+j `
                         -BriefDescription JumpDirectory `
                         -LongDescription "Goto the marked directory" `
                         -ScriptBlock {
    param($key, $arg)

    $key = [Console]::ReadKey()
    $dir = $global:PSReadLineMarks[$key.KeyChar]
    if ($dir)
    {
        Set-Location $dir
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }
}

Set-PSReadLineKeyHandler -Key Alt+j `
                         -BriefDescription ShowDirectoryMarks `
                         -LongDescription "Show the currently marked directories" `
                         -ScriptBlock {
    param($key, $arg)

    $global:PSReadLineMarks.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{Key = $_.Key; Dir = $_.Value} } |
        Format-Table -AutoSize | Out-Host

    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}


Function base64 {
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $textIn
    ) 
    
    $b = [System.Text.Encoding]::UTF8.GetBytes($textIn)
    $encoded = [System.Convert]::ToBase64String($b)
    return $encoded    
}

Function  debase64 {
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $textBase64In
    ) 
    
    $b = [System.Convert]::FromBase64String($textBase64In)
    $decoded = [System.Text.Encoding]::UTF8.GetString($b)
    return $decoded
}

Function guid {
    $guid = [System.Guid]::NewGuid()
    return $guid.ToString("D")
}