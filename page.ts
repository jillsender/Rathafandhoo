import { useEffect, useState } from 'react';
import { supabase } from './supabaseClient'; // adjust to your client path

interface PageSection {
  id: string;
  page_slug: string;
  section_label: string;
  title_en: string;
  title_dv: string;
  content_en: string;
  content_dv: string;
  image_url: string | null;
}

export function AdminPageEditor() {
  const [sections, setSections] = useState<PageSection[]>([]);
  const [selectedId, setSelectedId] = useState<string>('');
  const [form, setForm] = useState<PageSection | null>(null);
  const [uploading, setUploading] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    supabase
      .from('page_sections')
      .select('*')
      .order('page_slug')
      .then(({ data }) => {
        if (data && data.length > 0) {
          setSections(data);
          setSelectedId(data[0].id);
          setForm(data[0]);
        }
      });
  }, []);

  const handleSelect = (id: string) => {
    setSelectedId(id);
    const found = sections.find((s) => s.id === id) || null;
    setForm(found);
  };

  const handleImageUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !form) return;

    setUploading(true);
    const fileExt = file.name.split('.').pop();
    const filePath = `${form.page_slug}/${form.id}-${Date.now()}.${fileExt}`;

    const { error: uploadError } = await supabase.storage
      .from('page-media')
      .upload(filePath, file, { upsert: true });

    if (!uploadError) {
      const { data } = supabase.storage.from('page-media').getPublicUrl(filePath);
      setForm({ ...form, image_url: data.publicUrl });
    } else {
      alert(`Upload failed: ${uploadError.message}`);
    }
    setUploading(false);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form) return;

    setSaving(true);
    const { data: userData } = await supabase.auth.getUser();

    const { error } = await supabase
      .from('page_sections')
      .update({
        title_en: form.title_en,
        title_dv: form.title_dv,
        content_en: form.content_en,
        content_dv: form.content_dv,
        image_url: form.image_url,
        updated_at: new Date().toISOString(),
        updated_by: userData.user?.id ?? null,
      })
      .eq('id', form.id);

    setSaving(false);
    if (error) {
      alert(`Save failed: ${error.message}`);
    } else {
      setSections((prev) => prev.map((s) => (s.id === form.id ? form : s)));
      alert('Page updated successfully.');
    }
  };

  if (!form) return <div>Loading page sections...</div>;

  return (
    <form onSubmit={handleSave} className="space-y-4 max-w-2xl">
      <div>
        <label className="block font-medium mb-1">Select Page Section</label>
        <select
          value={selectedId}
          onChange={(e) => handleSelect(e.target.value)}
          className="border rounded p-2 w-full"
        >
          {sections.map((s) => (
            <option key={s.id} value={s.id}>
              [{s.page_slug.toUpperCase()}] {s.section_label}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label className="block font-medium mb-1">Section Picture</label>
        {form.image_url && (
          <img
            src={form.image_url}
            alt={form.section_label}
            className="h-40 w-full object-cover rounded mb-2 border"
          />
        )}
        <input
          type="file"
          accept="image/*"
          onChange={handleImageUpload}
          disabled={uploading}
        />
        {uploading && <p className="text-sm text-gray-500">Uploading image...</p>}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="block font-medium mb-1">Title (English)</label>
          <input
            type="text"
            value={form.title_en}
            onChange={(e) => setForm({ ...form, title_en: e.target.value })}
            className="border rounded p-2 w-full"
          />
        </div>
        <div>
          <label className="block font-medium mb-1">Title (Dhivehi)</label>
          <input
            type="text"
            dir="rtl"
            value={form.title_dv}
            onChange={(e) => setForm({ ...form, title_dv: e.target.value })}
            className="border rounded p-2 w-full"
          />
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="block font-medium mb-1">Content (English)</label>
          <textarea
            rows={5}
            value={form.content_en}
            onChange={(e) => setForm({ ...form, content_en: e.target.value })}
            className="border rounded p-2 w-full"
          />
        </div>
        <div>
          <label className="block font-medium mb-1">Content (Dhivehi)</label>
          <textarea
            rows={5}
            dir="rtl"
            value={form.content_dv}
            onChange={(e) => setForm({ ...form, content_dv: e.target.value })}
            className="border rounded p-2 w-full"
          />
        </div>
      </div>

      <button
        type="submit"
        disabled={saving || uploading}
        className="px-4 py-2 bg-blue-600 text-white rounded disabled:opacity-50"
      >
        {saving ? 'Saving...' : 'Save Changes'}
      </button>
    </form>
  );
}