// The 'mod1_token' program.
// En amont je regroupe les constantes et les variables globales
// utilisées dans le programme public, private, hybride

program mod1_token.aleo {
    // Adresse de l'administrateur qui peut frapper des tokens
    const ADMIN: address = aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px;
    
    // Ajout d'un système de taux de taxation (15 = 0.15%)
    const TAX: u16 = 15u16;
    
    // Mapping pour les soldes publics
    mapping balance: address => u64;
    
    // Mapping pour suivre les taxes dues par chaque adresse (pour les transactions privées)
    mapping taxes_due: address => u64;
    
    // Record pour les tokens privés
    record Token {
        owner: address,
        amount: u64
    }

    
    // ================== FONCTIONS PRIVÉES ==================
    
    // Frappe de tokens privés - uniquement par l'admin
    transition mint_private(private receiver: address, private amount: u64) -> Token {
        assert_eq(self.caller, ADMIN);
        
        let token: Token = Token {
            owner: receiver,
            amount: amount
        };
        
        return token;
    }
    
    // Transfert de tokens privés avec taxe
    transition transfer_private(
        old_token: Token,
        private receiver: address,
        private amount: u64
    ) -> (Token, Token) {
        // Calcul de la taxation
        let tax_amount: u64 = (amount * TAX as u64) / 10000u64;
        let transfer_amount: u64 = amount - tax_amount;
        
        // Vérification que le montant est suffisant (implicite dans la soustraction)
        let remaining_amount: u64 = old_token.amount - amount;
        
        // Token de change pour l'expéditeur
        let change_token: Token = Token {
            owner: old_token.owner,
            amount: remaining_amount
        };
        
        // Token pour le destinataire
        let receiver_token: Token = Token {
            owner: receiver,
            amount: transfer_amount
        };
        
        return (change_token, receiver_token);
    }
    
    // Fonction pour enregistrer la taxe après un transfert privé
    // Cette fonction doit être appelée par l'utilisateur après transfer_private
    async transition record_private_tax(private sender: address, private amount: u64) -> Future {
        // Calcul de la taxation
        let tax_amount: u64 = (amount * TAX as u64) / 10000u64;
        
        // Enregistrement de la taxe
        return finalize_record_tax(sender, tax_amount);
    }
    
    async function finalize_record_tax(sender: address, tax_amount: u64) {
        // Ajouter la taxe due pour cette adresse
        let current_tax: u64 = taxes_due.get_or_use(sender, 0u64);
        taxes_due.set(sender, current_tax + tax_amount);
    }
    
    // Fonction pour que l'admin collecte les taxes accumulées
    async transition collect_taxes(public from_address: address) -> Future {
        // Vérifier que seul l'admin peut collecter les taxes
        assert_eq(self.caller, ADMIN);
        
        return finalize_collect_taxes(from_address);
    }
    
    async function finalize_collect_taxes(from_address: address) {
        // Récupérer le montant de taxe dû par cette adresse
        let tax_amount: u64 = taxes_due.get_or_use(from_address, 0u64);
        
        if (tax_amount > 0u64) {
            // Ajouter le montant au solde public de l'admin
            let admin_balance: u64 = balance.get_or_use(ADMIN, 0u64);
            balance.set(ADMIN, admin_balance + tax_amount);
            
            // Réinitialiser les taxes dues pour cette adresse
            taxes_due.set(from_address, 0u64);
        }
    }
    
    // Fonction pour vérifier les taxes dues par une adresse
    async transition check_taxes_due(public address_to_check: address) -> Future {
        return finalize_check_taxes(address_to_check);
    }
    
    async function finalize_check_taxes(address_to_check: address) {
        // Cette fonction ne fait rien de plus que vérifier le mapping
        // La valeur sera visible dans la sortie de la fonction
        taxes_due.get(address_to_check);
    }
    
    // ============== FONCTIONS PUBLIQUES ==================
    
    // Création de tokens publics - uniquement par l'admin
    async transition mint_public(public receiver: address, public amount: u64) -> Future {
        assert_eq(self.caller, ADMIN);
        
        return finalize_mint(receiver, amount);
    }
    
    async function finalize_mint(receiver: address, amount: u64) {
        let old_balance: u64 = balance.get_or_use(receiver, 0u64);
        let new_balance: u64 = old_balance + amount;
        balance.set(receiver, new_balance);
    }
    
    // Transfert des tokens publics avec taxe
    async transition transfer_public(public receiver: address, public amount: u64) -> Future {
        return finalize_transfer(self.caller, receiver, amount);
    }
    
    async function finalize_transfer(sender: address, receiver: address, amount: u64) {
        // Calcul de la taxation
        let tax_amount: u64 = (amount * TAX as u64) / 10000u64;
        let transfer_amount: u64 = amount - tax_amount;
        
        // Ajout sur le solde du destinataire
        let receiver_old_balance: u64 = balance.get_or_use(receiver, 0u64);
        let receiver_new_balance: u64 = receiver_old_balance + transfer_amount;
        balance.set(receiver, receiver_new_balance);
        
        // Déduction du solde de l'expéditeur
        let sender_old_balance: u64 = balance.get_or_use(sender, 0u64);
        let sender_new_balance: u64 = sender_old_balance - amount;
        balance.set(sender, sender_new_balance);
        
        // On ajoute de la taxe à l'admin
        let admin_old_balance: u64 = balance.get_or_use(ADMIN, 0u64);
        let admin_new_balance: u64 = admin_old_balance + tax_amount;
        balance.set(ADMIN, admin_new_balance);
    }
    
    // ================== FONCTIONS DE CONVERSION ==================
    
    // Conversion privé -> public pour le modèle hybride
    async transition transfer_private_to_public(
        old_token: Token,
        private receiver: address,
        private amount: u64
    ) -> (Token, Future) {
        // Calcul de la taxation
        let tax_amount: u64 = (amount * TAX as u64) / 10000u64;
        let transfer_amount: u64 = amount - tax_amount;
        
        // Montant restant pour l'expéditeur
        let remaining_amount: u64 = old_token.amount - amount;
        
        // Token de change pour l'expéditeur
        let change_token: Token = Token {
            owner: old_token.owner,
            amount: remaining_amount
        };
        
        // Création de la future pour l'ajout du montant public
        let transfer_future: Future = finalize_private_to_public(receiver, transfer_amount, tax_amount);
        
        return (change_token, transfer_future);
    }
    
    async function finalize_private_to_public(receiver: address, transfer_amount: u64, tax_amount: u64) {
        // Ajout au solde du destinataire
        let receiver_old_balance: u64 = balance.get_or_use(receiver, 0u64);
        let receiver_new_balance: u64 = receiver_old_balance + transfer_amount;
        balance.set(receiver, receiver_new_balance);
        
        // Ajout de la taxe à l'admin
        let admin_old_balance: u64 = balance.get_or_use(ADMIN, 0u64);
        let admin_new_balance: u64 = admin_old_balance + tax_amount;
        balance.set(ADMIN, admin_new_balance);
    }
    
    // Conversion public -> privé avec taxation
    async transition transfer_public_to_private(
        private receiver: address,
        private amount: u64
    ) -> (Token, Future) {
        // Calcul de la taxation
        let tax_amount: u64 = (amount * TAX as u64) / 10000u64;
        let transfer_amount: u64 = amount - tax_amount;
        
        // Token pour le destinataire
        let receiver_token: Token = Token {
            owner: receiver,
            amount: transfer_amount
        };
        
        // Création de la future pour la déduction du montant public
        let transfer_future: Future = finalize_public_to_private(self.caller, amount, tax_amount);
        
        return (receiver_token, transfer_future);
    }
    
    async function finalize_public_to_private(sender: address, amount: u64, tax_amount: u64) {
        // Déduction du solde de l'expéditeur
        let sender_old_balance: u64 = balance.get_or_use(sender, 0u64);
        let sender_new_balance: u64 = sender_old_balance - amount;
        balance.set(sender, sender_new_balance);
        
        // Ajout de la taxe à l'admin
        let admin_old_balance: u64 = balance.get_or_use(ADMIN, 0u64);
        let admin_new_balance: u64 = admin_old_balance + tax_amount;
        balance.set(ADMIN, admin_new_balance);
    }
}