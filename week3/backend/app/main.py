# ============================================
# Week 3: Cloud Native Notes App 
# ============================================

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime

app = FastAPI(title="Cloud Native Notes")

# In-memory storage (no Redis yet)
notes_db = {}

class NoteCreate(BaseModel):
    title: str
    content: str

class NoteUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None

class Note(BaseModel):
    id: str
    title: str
    content: str
    created_at: datetime
    updated_at: datetime

@app.get("/health")
async def health():
    return {"status": "healthy", "week": 3, "notes_count": len(notes_db)}

@app.get("/")
async def root():
    return {
        "message": "Cloud Native Notes",
        "endpoints": ["/health", "/api/notes", "/api/notes/{id}"]
    }

@app.get("/api/notes", response_model=List[Note])
async def list_notes():
    return list(notes_db.values())

@app.post("/api/notes", response_model=Note, status_code=201)
async def create_note(note: NoteCreate):
    note_id = str(uuid.uuid4())[:8]
    now = datetime.utcnow()
    new_note = Note(
        id=note_id,
        title=note.title,
        content=note.content,
        created_at=now,
        updated_at=now
    )
    notes_db[note_id] = new_note
    return new_note

@app.get("/api/notes/{note_id}", response_model=Note)
async def get_note(note_id: str):
    if note_id not in notes_db:
        raise HTTPException(status_code=404, detail="Note not found")
    return notes_db[note_id]

@app.put("/api/notes/{note_id}", response_model=Note)
async def update_note(note_id: str, note: NoteUpdate):
    if note_id not in notes_db:
        raise HTTPException(status_code=404, detail="Note not found")
    
    existing = notes_db[note_id]
    if note.title:
        existing.title = note.title
    if note.content:
        existing.content = note.content
    existing.updated_at = datetime.utcnow()
    return existing

@app.delete("/api/notes/{note_id}")
async def delete_note(note_id: str):
    if note_id not in notes_db:
        raise HTTPException(status_code=404, detail="Note not found")
    del notes_db[note_id]
    return {"message": "Note deleted"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=3000)
