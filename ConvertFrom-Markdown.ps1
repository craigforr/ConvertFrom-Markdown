<#
.SYNOPSIS
    Converts a Markdown formatted text file to HTML.
.DESCRIPTION
    Converts a Markdown formatted text file to HTML using the Github API.

    Loosely based on PowerShell in a GitHub Gist by Lido Paglia:
    https://gist.github.com/lidopaglia/3739453

    ... which was based on the Ruby version by Brett Terpstra:
    http://brettterpstra.com/easy-command-line-github-flavored-markdown/

    About Markdown: http://daringfireball.net/projects/markdown/
.EXAMPLE
    Convert a basic markdown document named 'README.md' to HTML and put the output on the clipboard.

    ConvertFrom-Markdown -InputFile .\README.md -MarkdownFlavor Markdown | clip
.EXAMPLE
    Convert a basic markdown document named 'howto.md' to an HTML file named 'howto.html' using a template named 'template.html', a Title and Subtitle, and omitting the first heading element in the input file. In this case, the template has its own placeholders for the values specified with the Title and Subtitle parameters.

    ConvertFrom-Markdown -InputFile .\howto.md -MarkdownFlavor Markdown -TemplatePath .\template.html -OutputFile howto.html -Title 'Markdown HOWTO' -Subtitle 'The Basics of Markdown' -IgnoreFirstHeading
.INPUTS
    None.
.NOTES
    v1.0
      Author: Craig Forrester
      Date: 2017-05-30T22:00-04:00
      Changes: Initial version
.LINK
    https://github.com/craigforr/ConvertFrom-Markdown
#>

# function ConvertFrom-Markdown {
    [CmdletBinding()]
    Param(
        [Parameter(
            HelpMessage = 'Markdown file to convert',
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        [ValidateScript({Test-Path $_})]
        [string]$InputFile,
        [Parameter(
            HelpMessage = 'The rendering mode. Can be either Markdown or GFM.',
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 1)]
        [ValidateSet("Markdown","GFM")]
        [string]$MarkdownFlavor = 'Markdown',
        [Parameter(
            HelpMessage = 'File in which to save converted HTML output',
            Mandatory = $false,
            ValueFromPipeline = $true)]
        [string]$OutputFile,
        [Parameter(
            HelpMessage = 'The repository context taken into account when rendering as GFM.',
            Mandatory = $false,
            ValueFromPipeline = $true)]
        [string]$GitHubContext,
        [Parameter(
            HelpMessage = 'HTML template for converted document',
            Mandatory = $false,
            ValueFromPipeline = $true)]
        [string]$TemplatePath,
        [Parameter(
            HelpMessage = 'Title of the document',
            Mandatory = $false,
            ValueFromPipeline = $false)]
        [string]$Title,
        [Parameter(
            HelpMessage = 'Subtitle of the document',
            Mandatory = $false,
            ValueFromPipeline = $false)]
        [string]$SubTitle,
        [Parameter(
            HelpMessage = 'If specified only the inner HTML content will be returned',
            Mandatory = $false,
            ValueFromPipeline = $false)]
        [switch]$NoTemplate,
        [Parameter(
            HelpMessage = 'Whether the first H1 element should be skipped in the HTML output',
            Mandatory = $false,
            ValueFromPipeline = $false)]
        [switch]$IgnoreFirstHeading
    )

    Begin {
        # GitHub Public API
        $api_url = 'https://api.github.com/markdown'

    }
    Process {

        # Only process a single file
        $file = $InputFile | Select-Object -First 1

        if (Test-Path -Path $file) {
            # Assume ATX style headings
            # TODO: Fix this handling to account for Setext-style headings also
            # https://github.github.com/gfm/#setext-heading
            #
            if ($IgnoreFirstHeading) {
                # If the user specified a title at runtime, skip the first two lines,
                # which should be the first H1 and a blank line
                $i = 0
                $content = Get-Content -Path $file | ForEach-Object { if ($i -ge 2) { $_ } ; $i += 1 }
            } else {
                $content = Get-Content -Path $file
            }

            $object = New-Object -TypeName psobject
            $object | Add-Member -MemberType NoteProperty -Name 'text' -Value ($content | Out-String)

            switch ($MarkdownFlavor) {
                "GFM" {
                    # GitHub Flavored Markdown (GFM)
                    $object | Add-Member -MemberType NoteProperty -Name 'mode' -Value 'gfm'
                    $object | Add-Member -MemberType NoteProperty -Name 'context' -Value $GitHubContext
                }
                Default {   
                    # Standard Markdown
                    $object | Add-Member -MemberType NoteProperty -Name 'mode' -Value 'markdown'
                }
            }
            $response = Invoke-WebRequest -Method Post -Uri $api_url -Body ($object | ConvertTo-Json)

            if ($response.StatusCode -eq "200") {

                if ($Title) {
                    # Override automatically generated title with Title specified at runtime
                    $document_title = $Title
                } else {
                    # If no Title was specified at runtime, then try to use the first ATX-Style H1 element
                    try {
                        $document_title = Get-Content $file | ForEach-Object {
                            if ($_ -match '^# ') {
                                $_.Trim('# ')
                            }
                        } | Select-Object -First 1
                    } catch {
                        Write-Warning "Error automatically processing document title."
                        Write-Warning "$_"
                    } finally {
                    }
                }
                if ($SubTitle) {
                    $document_subtitle = $SubTitle
                } else {
                    $document_subtitle = 'Document'                        
                }
                $document_content = $($response.Content)

                # Default HTML Template for use in conversion
                $template_default = @"
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="utf-8">
                    <title>${document_title}</title>
                </head>
                <body>
                    ${document_content}
                </body>
                </html>
"@ # For the herestring to be valid, this closing quote cannot be indented

                # Use a template file if one was supplied, otherwise use default
                if ($TemplatePath) {
                    $html = Get-Content -Raw -Path $TemplatePath
                    $output = $ExecutionContext.InvokeCommand.ExpandString($html)
                } else {
                    $html = $template_default
                    $output = $html
                }

                # Write output to file if requested, otherwise use stdout
                if ($OutputFile) {
                    Set-Content -Path $OutputFile -Value $output
                } else {
                    $output
                }

            } else {
                Write-Error "Return status was $($response.StatusCode)"
            }
        } else {
            Write-Warning "File `"$file`" could not be found."
        }
    }

    End {
        Write-Verbose "Output written to: ${OutputFile}."
    }
# }
