const admin = require('firebase-admin');

// 1. Conectarea la Firebase folosind cheia secretă din GitHub
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const db = admin.firestore();
const messaging = admin.messaging();

async function run() {
  console.log('🤖 Incep verificarea produselor...');
  const now = new Date();
  
  // 2. Extragem toate jetoanele (FCM Tokens) ale utilizatorilor
  const usersSnap = await db.collection('users').get();
  const userTokens = {};
  usersSnap.forEach(doc => {
    const data = doc.data();
    if (data.fcmToken) userTokens[doc.id] = data.fcmToken;
  });

  // 3. Luăm toate gospodăriile
  const householdsSnap = await db.collection('households').get();
  
  for (const householdDoc of householdsSnap.docs) {
    const household = householdDoc.data();
    const members = household.members || [];
    
    // Găsim token-urile pentru membrii acestei gospodării
    const tokensToSend = members.map(uid => userTokens[uid]).filter(token => token);
    if (tokensToSend.length === 0) continue; // Sarim daca nimeni nu are notificari pornite

    // 4. Verificăm inventarul gospodăriei
    const inventorySnap = await db.collection('households').doc(householdDoc.id).collection('inventory').where('isConsumed', '==', false).get();
    
    let expiringItems = [];

    inventorySnap.forEach(itemDoc => {
      const item = itemDoc.data();
      if (!item.batches || item.batches.length === 0) return;

      item.batches.forEach(batch => {
        if (!batch.expiryDate) return;
        
        // Convertim data din Firebase in data de Javascript
        const expiry = batch.expiryDate.toDate ? batch.expiryDate.toDate() : new Date(batch.expiryDate);
        
        // Calculam diferenta de zile
        const diffTime = expiry - now;
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));

        // Dacă expiră în 3 zile sau mai puțin (și nu a expirat de mai mult de 2 zile)
        if (diffDays <= 3 && diffDays >= -2) {
          expiringItems.push(`${item.name} (${diffDays > 0 ? 'în ' + diffDays + ' zile' : 'expirat'})`);
        }
      });
    });

    // 5. Trimitem notificarea dacă am găsit produse
    if (expiringItems.length > 0) {
      const message = {
      notification: {
        title: `⚠️ Alerte expirare în ${household.name}`,
        body: `Ai ${expiringItems.length} produse care expiră curând...`
      },
      android: {
        priority: 'high',
      },
      tokens: tokensToSend,
    };

      try {
        const response = await messaging.sendEachForMulticast(message);
        console.log(`✅ Notificare trimisă pentru ${household.name}: ${response.successCount} primite.`);
      } catch (error) {
        console.error(`❌ Eroare la trimitere pentru ${household.name}:`, error);
      }
    }
  }
}

run().then(() => {
  console.log('🏁 Verificare finalizata.');
  process.exit(0);
}).catch(err => {
  console.error('❌ Eroare critica:', err);
  process.exit(1);
});