import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
// Ganti ke default import
import admin from "npm:firebase-admin@11.10.1";

const serviceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT") || "{}");

// Inisialisasi Firebase dengan cara yang lebih aman
if (!admin.apps || admin.apps.length === 0) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

serve(async (req) => {
  const supabaseClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  try {
    const payload = await req.json();
    const record = payload.record;
    const old_record = payload.old_record;

    // Filter: Hanya jalankan jika status benar-benar berubah
    if (!record || (old_record && record.status === old_record.status)) {
      return new Response(JSON.stringify({ message: "Status tidak berubah, skip notifikasi" }), { status: 200 });
    }

    // Ambil token karyawan
    const { data: employee, error } = await supabaseClient
      .from("employees")
      .select("fcm_token, full_name")
      .eq("id", record.employee_id)
      .single();

    if (error || !employee?.fcm_token) {
      throw new Error("Token tidak ditemukan");
    }

    // Kirim notifikasi
    const message = {
      token: employee.fcm_token,
      notification: {
        title: "Update Status Pengajuan",
        body: `Halo ${employee.full_name}, pengajuan Anda kini: ${record.status?.toUpperCase()}`,
      },
    };

    await admin.messaging().send(message);

    return new Response(JSON.stringify({ message: "Notifikasi terkirim" }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Error details:", err);
    return new Response(JSON.stringify({ error: err.message }), { status: 400 });
  }
});