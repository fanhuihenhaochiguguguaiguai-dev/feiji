"""Creates original avionics and reward artwork for the inventory registry."""
from pathlib import Path
root=Path(__file__).resolve().parent/'icon-blueprints';root.mkdir(exist_ok=True)
drawings={
'credits':'<path d="m96 20 43 25v43l-43 25-43-25V45z M96 35l29 16v30L96 98 67 81V51z"/><path d="m78 64 13 8 23-20M95 44v45"/>',
'interceptor':'<path d="m40 89 68-52 46-6-22 36-74 38z M58 78l-19 3-12 19 31-7m55-43 1-24 23 11m-24 19 23 10-23 15-20-7"/><path d="m65 73 29 2"/>',
'flarewing':'<path d="m46 79 65-38 36-2-15 28-68 33z M49 79 31 66l-6 19 15 11m35-20-14-29 27 5m6 36 30 10 11-17-21-9"/><circle cx="136" cy="44" r="6"/>',
'skylance':'<path d="m29 97 108-67 41-8-20 32-111 61z M57 80l-21-21-8 21 14 8m29 6 27 11 24-19-20-4m28-37 1-17 18 5"/><path d="m74 83 48-28"/>',
'vector':'<path d="M49 39h81l29 20v31l-29 16H49z M49 42c-25 0-25 61 0 61 24 0 24-61 0-61m21 2 39 10v33l-39 10m48-40 29 10v14l-29 8"/><path d="m40 58 19 27m3-28-22 29"/>',
'survey':'<path d="M56 68a40 40 0 0 1 80 0l-40 30z M72 66a24 24 0 0 1 48 0M66 107h62 M96 97v12m1-38 27-49"/><circle cx="104" cy="60" r="5"/>',
'veil':'<path d="M65 42 96 27l31 15v39l-31 24-31-24z M96 47l17 10v18l-17 14-17-14V57zM48 46a55 55 0 0 0 0 43m96-43a55 55 0 0 1 0 43"/>',
'factory':'<path d="m32 81 83-48 48 5-30 67-47 7z"/><path d="m52 80 42-27 42 8-54 37z" opacity=".6"/>',
'navy':'<path d="m32 78 78-45 49 8-24 64-53 6z"/><path d="m50 80 42-27 42 8-54 37m-34-5 34 12 43-25" opacity=".6"/>',
'sand':'<path d="m32 78 78-45 49 8-24 64-53 6z"/><path d="m48 81 32 12-9 9m3-56 38 15-15 13 40 18m-29-57 15 17 27 9"/>',
'night':'<path d="m30 84 66-48 62-3-29 71-52 8z"/><path d="m49 88 56-37 39 3m-79 48 63-11" opacity=".7"/>',
'bronze-sky':'<path d="m30 84 66-48 62-3-29 71-52 8z"/><path d="m49 88 56-37 39 3m-79 48 63-11"/><path d="m111 22 6-13m25 18 15-9"/>',
'cannon-light':'<path d="M28 82h45l85-35 11 8-89 43H31z M74 83l20-19 17 5m25-12 12 8m-110 34 9-17"/>',
'cannon-jet':'<path d="m28 76 37-10 85-34 13 6 9 14-103 46-41-4z M67 74l9 14m15-25 7 16m23-27 7 12m14-24 7 13"/>',
'cannon-heavy':'<path d="m20 77 111-53 40 4v30L57 112l-34-8z M35 76l102-40m-90 51 107-47m-97 59 104-47m-35-24 11 34m-45-20 10 36"/>',
'shorebolt':'<path d="m38 82 79-45 36 3 13 16-33 18-72 26z M62 69l-11-20-18 13 11 16m74-25 7 12m-27 18 6 18-19 12-10-18"/>',
'bomb':'<path d="m59 87 18-39 24-14 48 9-14 47-35 24z M81 56 47 34l-7 32 24 17m42 15 45 4-16-19"/><path d="m112 40 31 13"/>',
 'xp':'<path d="M95 12l14 30 33 5-23 25 6 35-30-17-30 17 6-35-23-25 33-5z M95 31l7 20 21 4-15 14 4 20-17-9-17 9 4-20-15-14 21-4z"/><path d="M45 31 32 49l7 23m109-41 13 18-8 23M55 103l13 13h53l15-14"/>',
'up-engine':'<path d="M31 45h29l18-17h62l19 19v39l-20 16H78L59 86H31zM64 67a23 34 0 1 1-45 0 23 34 0 1 1 45 0zM45 45v43m-16-30 27 17M27 76l31-19M79 44h63m-62 15h67m-65 17h65m-65 15h58"/><path d="m160 57 17 9-17 10m12-29 16 19-16 21"/>',
'up-maneuver':'<path d="M30 88l58-53 68-11-41 49-54 32z M81 40l22 26-42 39m70-51 24 17-39 34-24-14m37-64 10 11-21 16"/><path d="M23 48a50 50 0 0 1 43-27l-8-8m9 8-6 9m94 69 11-10-1 17"/>',
'up-armor':'<path d="m40 83 44-50 63-7-28 49-60 31z M47 98l51 6 50-31 13-37m-86 78 34 2 44-36 9-41M70 83l24-28 30-8-17 24z"/><circle cx="61" cy="86" r="4"/><circle cx="133" cy="38" r="4"/><circle cx="109" cy="77" r="4"/>',
'up-radar':'<path d="M46 62h100v33H46z M83 73h27v12H83zM64 65l-16 17 15 12m61-29 17 16-10 10M66 107h61m-30-12v13M51 47a61 61 0 0 1 90 0M66 50a44 44 0 0 1 61 0m-44 3a21 21 0 0 1 25 0"/><circle cx="96" cy="30" r="4"/>',
'up-weapons':'<path d="m35 92 98-67 27 6 8 23-104 67-28-9zM44 85l24 22m-6-33 23 24m-7-36 22 26m-5-37 22 24m-7-35 24 24m1-36 21 24"/><path d="m17 103 11-16m-8 31 14-13m129-81 15-10m-5 22 13-11"/>',
'up-warhead':'<path d="m44 84 71-57 34-3 17 19-21 33-66 44-27-9zM97 41l31 31m-47-19 31 31m-58-10 25 35m43-79 28 26m-6-27 16-12M41 97l-15 4m20 11-9 12m112-31 17-8"/>',
}
colors={'flarewing':'#ff9375','skylance':'#95e8ff','survey':'#7ad9d9','navy':'#7dbcec','bronze-sky':'#eab677','night':'#8792bd','xp':'#a8d4ea','up-engine':'#ffb47a','up-maneuver':'#aeceff','up-armor':'#d2bc99','up-radar':'#8be1d3','up-weapons':'#eeb18b'}
for key,art in drawings.items():
    color=colors.get(key,'#eccb95')
    content=f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 192 132">
    <defs><linearGradient id="field" x2="0.8" y2="1"><stop stop-color="#29495f"/><stop offset=".56" stop-color="#122a40"/><stop offset="1" stop-color="#091922"/></linearGradient>
    <pattern id="grid" width="12" height="12" patternUnits="userSpaceOnUse"><path d="M12 0H0V12" fill="none" stroke="#75a1b6" stroke-opacity=".16"/></pattern>
    <radialGradient id="metal"><stop stop-color="{color}" stop-opacity=".48"/><stop offset="1" stop-color="{color}" stop-opacity=".045"/></radialGradient></defs>
    <path d="M14 4h162l12 14v96l-12 14H14L4 115V18z" fill="url(#field)" stroke="#7697ae" stroke-width="1.2"/>
    <path d="M14 4h162l12 14v96l-12 14H14L4 115V18z" fill="url(#grid)"/>
    <path d="M15 18v-6h17m127 0h17v6m0 96v6h-17m-127 0H15v-6" fill="none" stroke="{color}" stroke-opacity=".75"/>
    <g fill="url(#metal)" stroke="{color}" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round">{art}</g></svg>'''
    (root/(key+'.svg')).write_text(content)
