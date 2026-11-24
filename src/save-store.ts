export interface PilotSnapshot { savedAt:number; data:string; }

const store='snapshots';
let opening:Promise<IDBDatabase|null>|undefined;

function database(){
  return opening??=new Promise(resolve=>{
    if(typeof indexedDB==='undefined'){resolve(null);return;}
    try{
      const request=indexedDB.open('cangqiong-pilot',1);
      request.onupgradeneeded=()=>request.result.createObjectStore(store);
      request.onsuccess=()=>{
        const db=request.result;
        db.onversionchange=()=>{db.close();opening=undefined;};
        resolve(db);
      };
      request.onerror=request.onblocked=()=>resolve(null);
    }catch{resolve(null);}
  });
}

export async function readSnapshots():Promise<PilotSnapshot[]>{
  const db=await database();
  if(!db)return [];
  return new Promise(resolve=>{
    try{
      const tx=db.transaction(store),records=tx.objectStore(store);
      const current=records.get('current'),previous=records.get('previous');
      tx.oncomplete=()=>resolve([current.result,previous.result].filter(Boolean));
      tx.onabort=()=>resolve([]);
    }catch{resolve([]);}
  });
}

export async function persistSnapshot(value:PilotSnapshot){
  const db=await database();
  if(!db)return;
  try{
    const tx=db.transaction(store,'readwrite'),records=tx.objectStore(store);
    const current=records.get('current');
    current.onsuccess=()=>{
      const last=current.result as PilotSnapshot|undefined;
      if(last&&last.savedAt>=value.savedAt)return;
      if(last)records.put(last,'previous');
      records.put(value,'current');
    };
  }catch{/* The synchronous recovery journal already holds the successful write. */}
}
