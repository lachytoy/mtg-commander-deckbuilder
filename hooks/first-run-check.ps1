# SessionStart hook for the MTG Commander Deckbuilder plugin.
# If no collection has been imported yet, inject a hint so Claude offers the
# first-run setup wizard. Emits nothing once a collection exists (stays quiet).
# Output contract: print JSON with hookSpecificOutput.additionalContext.
$ErrorActionPreference = 'SilentlyContinue'

$ws = $env:MTG_WORKSPACE
$imported = $false
if ($ws) { $imported = Test-Path (Join-Path $ws 'data\owned-cards.json') }

if (-not $imported) {
  $msg = 'The MTG Commander Deckbuilder plugin is installed, but no card collection has been imported yet. ' +
         'Proactively offer to run the first-run setup wizard (the "mtg-setup" skill): it walks the user through ' +
         'choosing a workspace folder, exporting their Moxfield collection, importing it, and building their first ' +
         'Commander deck. The user can also just say "set up my MTG deckbuilder".'
  $payload = @{ hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = $msg } }
  $payload | ConvertTo-Json -Compress -Depth 5
}
