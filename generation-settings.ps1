function Get-AImageQualityChoices {
    param([Parameter(Mandatory = $true)]$Model)

    if ($Model.Id -eq 'lustify-v10-krea2-turbo') {
        return @(
            [pscustomobject]@{ Name = 'Preview'; Width = 512; Height = 512; Steps = 8; Description = 'composition only; softer detail' },
            [pscustomobject]@{ Name = 'Standard'; Width = 768; Height = 768; Steps = 8; Description = 'balanced speed and detail' },
            [pscustomobject]@{ Name = 'Quality'; Width = 1024; Height = 1024; Steps = 8; Description = 'native detail; recommended for final photographs' }
        )
    }
    if ($Model.Id -eq 'lustify-zenith-v9') {
        return @(
            [pscustomobject]@{ Name = 'Preview'; Width = 768; Height = 768; Steps = 16; Description = 'quick composition check' },
            [pscustomobject]@{ Name = 'Standard'; Width = 1024; Height = 1024; Steps = 20; Description = 'native detail; balanced speed' },
            [pscustomobject]@{ Name = 'Quality'; Width = 1024; Height = 1024; Steps = 30; Description = 'more refinement; about 50% more sampling work' }
        )
    }
    return @([pscustomobject]@{
        Name = 'Native'; Width = $Model.Width; Height = $Model.Height; Steps = $Model.Steps
        Description = 'original model settings'
    })
}

function Get-AImagePromptSettings {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$Model,
        [ValidateSet('Original', 'Natural', 'Realistic')][string]$Appearance = 'Original',
        [ValidateSet('Auto', 'FullBody', 'Portrait', 'Wide')][string]$PhotoComposition = 'Auto',
        [ValidateSet('Text to image', 'Start from image', 'Edit image')][string]$ImageMode = 'Text to image'
    )

    $effective = $Prompt.Trim()
    $negative = ''
    if ($Appearance -eq 'Natural') {
        # Avoid imposing a camera angle, light source, lens, or subject. Those
        # belong to the user's description and may also be fixed by an input image.
        $effective += '. Photographic rendering with natural colors, realistic material textures, subtle tonal transitions, and physically plausible light and shadow.'
        if ($Model -eq 'lustify-zenith-v9') {
            $negative = 'illustration, painting, cartoon, CGI, 3D render, plastic skin, overprocessed, oversharpened, oversaturated, watermark'
        }
        # Turbo has CFG=1: negative conditioning would add cost without the
        # conventional CFG effect. Keep its eight-step distilled sampler intact.
    }
    $composition = ''
    if ($Appearance -eq 'Realistic') {
        # Put the photographic style before the subject, and keep guidance short:
        # long generic instruction lists can dilute the scene and add work.
        $photoLead = 'A realistic, unretouched photograph of '
        $resolvedComposition = $PhotoComposition
        $hasGroup = $Prompt -match '(?i)\b(people|persons|men|women|children|friends|family|families|crowd|hikers|adults|workers|guests|teammates|dancers|players|students|tourists|pedestrians|colleagues|siblings)\b|\bcouples?\b(?!\s+of\b)|\b(?:man|woman|person|adult|hiker)\s+and\s+(?:an?\s+)?(?:man|woman|person|adult|hiker)\b'
        $hasPerson = $hasGroup -or $Prompt -match '(?i)\b(man|woman|person|child|hiker|adult|worker|guest|teammate|dancer|player|student|tourist|pedestrian|colleague)\b'
        if ($ImageMode -eq 'Text to image') {
            if ($PhotoComposition -eq 'Auto') {
                # Conservative English framing hints: an explicit crop takes
                # precedence. Other languages can use the framing menu directly.
                $explicitCrop = $Prompt -match '(?i)\b(headshot|close[ -]?up|macro|cropped|waist[ -]?up|chest[ -]?up|head[ -]and[ -]shoulders|(?:face|head|hands?|feet) only)\b'
                if ($explicitCrop -or (-not $hasGroup -and $Prompt -match '(?i)\bportrait\b')) {
                    $resolvedComposition = 'Auto'
                } elseif ($hasPerson) {
                    $resolvedComposition = 'FullBody'
                } else { $resolvedComposition = 'Wide' }
            }
            switch ($resolvedComposition) {
                'FullBody' {
                    $photoLead = if ($hasGroup) {
                        'A realistic, unretouched full-body group photograph. Every person is fully visible head to toe, with all feet inside the frame: '
                    } else { 'A realistic, unretouched full-body photograph, showing the entire subject from head to feet: ' }
                }
                'Portrait' { $photoLead = 'A realistic, unretouched head-and-shoulders portrait photograph of ' }
                'Wide' { $photoLead = 'A realistic, unretouched wide environmental photograph, showing the whole main subject in its surroundings: ' }
            }
            # This checkpoint can infer nudity from a bare "person" description.
            # Fill only missing clothing; leave explicit wardrobe/undress intact.
            if ($hasPerson -and $Prompt -notmatch '(?i)\b(wear\w*|dress\w*|clothes|clothing|outfit|uniform|garment\w*|shirt\w*|trousers|pants|jeans|shorts|skirt\w*|jacket\w*|coat\w*|suit\w*|sweater\w*|hoodie\w*|swim\w*|bikini\w*|underwear|lingerie|nude|nudity|naked|unclothed|undressed|bare|shirtless|topless)\b') {
                $effective += ', wearing ordinary casual clothing'
            }
            if ($hasPerson -and $resolvedComposition -in @('FullBody','Wide') -and
                $Prompt -match '(?i)\bplastic bottles?\b' -and $Prompt -match '(?i)\b(garbage|litter|discarded|trash|rubbish)\b' -and
                $Prompt -notmatch '(?i)\b(giant|huge|oversized|enormous|colossal)\b') {
                $effective += '. Small discarded plastic bottles lie on the ground near the person, well below knee height'
            }
        }
        $effective = if ($ImageMode -eq 'Text to image') { $photoLead + $effective } else { 'Keep a realistic photographic appearance. ' + $effective }
        $effective += '. True-to-life facial features and proportions, anatomically connected body parts appropriate to the subject, ordinary object sizes, consistent perspective, believable surface contact and shadows. Natural material and skin textures, lighting consistent with the setting. Preserve the described action and pose.'
        if ($ImageMode -eq 'Text to image') {
            $composition = $PhotoComposition
            switch ($resolvedComposition) {
                'FullBody' {
                    if ($hasGroup) {
                        $effective += ' Frame wide enough for the whole group, with space below every person and clear sightlines so bodies do not hide each other.'
                    } else {
                        $effective += ' Use a full-body photograph: show the principal person or animal completely, from head to feet or paws, with room around them and a visible supporting surface. Keep nearby objects at their normal scale.'
                    }
                }
                'Portrait' { $effective += ' Use a head-and-shoulders portrait, showing the head naturally connected to the neck and shoulders, with surroundings behind the subject.' }
                'Wide' { $effective += ' Use a wide environmental photograph, showing the whole main subject within the surroundings, with foreground, middle distance, and background at consistent scale.' }
                'Auto' { $effective += ' When framing is unspecified, show the whole main subject within its surroundings. Preserve any explicitly requested close-up or pose.' }
            }
            if ($hasGroup) {
                $effective += ' Preserve the requested headcount, appearances, positions and activities. Where unspecified, vary individual looks, postures, gaze, gestures and small actions to fit the scene. Use relaxed body language, natural spacing and slight differences in depth where the scene allows.'
            }
        } else {
            # An instruction edit or source-image redraw must not acquire a new
            # pose, framing, or new objects merely because assistance is enabled.
            $effective += ' Preserve the source composition and body placement except where the description explicitly requests a change.'
        }
        if ($Model -eq 'lustify-zenith-v9') {
            $negative = 'illustration, painting, cartoon, CGI, 3D render, plastic skin, overprocessed, oversharpened, oversaturated, watermark, disembodied head, disconnected limbs, fused objects, distorted anatomy, exaggerated proportions'
        }
    }
    return [pscustomobject]@{
        Prompt = $effective; NegativePrompt = $negative; PhotoComposition = $composition
        ResolvedPhotoComposition = if ($composition) { $resolvedComposition } else { '' }
    }
}
