
function getUrlParam(key) {
	key = key.replace(/[\[]/, '\\[').replace(/[\]]/, '\\]')
	var regex = new RegExp('[\\?&]' + key + '=([^&#]*)')
	var results = regex.exec(location.search)
	return results === null ? null : decodeURIComponent(results[1].replace(/\+/g, ' '))
}

// show snack bar
function showSnackbar(text) {
  $('<div>', {
    id: 'snackbar',
    text: text
  }).appendTo('body');
  $('#snackbar').addClass('show');
  setTimeout(function(){
    $('#snackbar').remove();
  }, 2000);
}


function onMetaMaskConnected(account) {
	console.log("Connected to MetaMask", account)
	$('#connect-metamask').hide()
	$('#button-metamask').hide()
	$('#main').show()
	showSnackbar("Connected to MetaMask")
}

function onMetaMaskDisconnected() {
	console.log("Disconnected from MetaMask")
	$('#connect-metamask').show()
	$('#button-metamask').show()
	$('#main').hide()
	showSnackbar("Disconnected from MetaMask")
}

function onMetaMaskAccountsChanged(accounts) {
	console.log("onMetaMaskAccountsChanged", accounts)
	if (accounts.length === 0) {
		onMetaMaskDisconnected()
		return
	}
	onMetaMaskConnected(accounts[0])
}

function onClickMetaMask() {
	if(!window.ethereum) {
		return
	}
	window.ethereum.request({ method: 'eth_requestAccounts' })
	.then(onMetaMaskAccountsChanged)
	.catch((err) => {
		console.log("error", err)
	})
}

async function sendCongrats(provider, sender, receiver, message, ether) {
	const tx = {}
	tx.from = sender
	tx.to = receiver
	if (message) {
		tx.data = ethers.utils.toUtf8Bytes(message)
	}
	if (ether) {
		tx.value = ethers.utils.parseEther(ether)
	}

	const signer = provider.getSigner()
	signer.sendTransaction(tx)
	.then((txObj) => {
		console.log(txObj)
	})

}

async function onClickSend() {
	console.log("onClickSend")

	if(!window.ethereum) {
		alert("Please connect to MetaMask")
		return
	}

	const provider = new ethers.providers.Web3Provider(window.ethereum)

	const sender = window.ethereum.selectedAddress
	if (!sender) {
		alert("Please connect to MetaMask")
		return
	}

	const receiver = $('#input-eth-address').val()

	if (!ethers.utils.isAddress(receiver)) {
		const address = await provider.getSigner().resolveName(receiver)
		if (!ethers.utils.isAddress(address)) {
			alert("Enter valid ether address")
			return
		}
	}

	const message = $('#input-message').val()
	const ether = $('#input-eth-val').val()

	try {
		sendCongrats(provider, sender, receiver, message, ether)
	} catch (e) {
		console.log(e)
		alert(e.message)
	}
}

function registerEthereumEvents() {

	ethereum.on('accountsChanged', (accounts) => {
		console.log("accountChanged", accounts)
		onMetaMaskAccountsChanged(accounts)
	})

	ethereum.on('chainChanged', (chainId) => {
		console.log("chainChanged", chainId)
 	})
}

$(()=> {
	console.log("on loaded")
	if(!window.ethereum) {
		return
	}
	registerEthereumEvents()
})