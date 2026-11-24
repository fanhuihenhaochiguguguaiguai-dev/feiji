const shapes:Record<string,string>={
  wing:'M2 7l8 3 2 4 2-4 8-3-4 9-6 4-6-4z M12 3v6',plane:'M11 2l2 0 1 7 8 5v2l-8-2v5l3 2v1l-5-1-5 1v-1l3-2v-5l-8 2v-2l8-5z',
  home:'M3 11l9-8 9 8 M6 10v11h12V10 M10 21v-6h4v6',star:'m12 2 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z',
  settings:'M10 2h4l1 3 3 1 3 4-2 2 1 4-3 3-3-1-2 4-4-1-1-3-3-1-3-4 2-2v-4l3-3 3 1z M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0',
  target:'M19 6l-7-4-7 4v7l7 8 7-8z M12 7v8M8 11h8',gift:'M3 9h18v4H3z M5 13v8h14v-8 M12 9v12 M12 9C7 8 6 2 9 3c2 0 3 4 3 6 0-2 1-6 3-6 3-1 2 5-3 6z',
  base:'M2 20h20M4 20V8l8-4 8 4v12M8 20v-8h8v8M2 8l10-5 10 5',record:'M5 4h14v17H5zM8 8h8m-8 4h8m-8 4h5',left:'m15 5-7 7 7 7',right:'m9 5 7 7-7 7',
  tools:'M14 3c5-1 8 3 6 7-1 2-3 3-5 3l-8 8a2 2 0 1 1-3-3l8-8c-1-3 0-6 2-7l2 4 3-1',
  tree:'M12 3v5m0 8v5M4 8h16v8H4z M4 12H2m18 0h2',pause:'M8 5h2v14H8zM14 5h2v14h-2z',
  view:'M3 12s4-6 9-6 9 6 9 6-4 6-9 6-9-6-9-6zM15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0',
  evade:'M3 20 9 9l4 5 5-10m-5 0h5v5M3 13l3-3m8 11 4-4',
  boost:'m4 15 8-11 8 11m-14 5 6-7 6 7',lock:'M8 3H3v5m13-5h5v5m-5 13h5v-5m-13 5H3v-5m9-8v8m-4-4h8',
  missile:'m20 3-2 8-7 7-4-3L20 3zm-9 15-3 3-5-1 4-5m5 2 1 4 5-4 1-5M3 16l3-3',bomb:'M15 7l4-5 3 3-4 4m-3-2a7 7 0 1 0 4 7L15 7z',cross:'M6 10l6-7 6 7m-6-7v18m-7-4h14',
  switch:'M3 7h17l-4-4m5 14H4l4 4m12-14-4 4M4 17l4-4',
  shield:'M12 2l8 4v8c0 2-4 6-8 8-4-2-8-6-8-8V6zM12 6v11',
  fullscreen:'M10 4H4v6m10-6h6v6m0 4v6h-6m-4 0H4v-6M9 9l-2-2m8 2 2-2m0 10-2-2m-6 0-2 2',
  cannon:'M7 14l8-8 4 4-8 8H7zm8-8 2-2 4 4-2 2M5 16l-2 2 3 3 2-2M13 10l4 4M9 14l4 4m6-14 2-2m1 9 2-2',
  deflect:'M3 14l2 4 7 4 7-4 2-4M6 10l6 7 6-7m-6-7v9M8 5l-2 2m10-2 2 2M4 5l-2-2m18 2 2-2',
  map:'M2 5l6-2 8 2 6-2v16l-6 2-8-2-6 2zM8 3v16M16 5v16',close:'m5 5 14 14M19 5 5 19',check:'m4 12 5 5L20 6'
};
export function icon(name:string){
  if(name==='coin')return '<img class="credit-mark" src="./items/credits-wallet.webp" alt="" width="34" height="25" decoding="async">';
  return '<svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.55" stroke-linecap="round" stroke-linejoin="round"><path d="'+(shapes[name]??shapes.star)+'"/></svg>';
}
export function icons(root:ParentNode=document){
  root.querySelectorAll<HTMLElement>('[data-icon]').forEach(el=>el.innerHTML=icon(el.dataset.icon!));
  root.querySelectorAll<HTMLElement>('[data-icon-label]').forEach(el=>el.insertAdjacentHTML('afterbegin',icon(el.dataset.iconLabel!)));
}
