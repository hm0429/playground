
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

function loadTx(address, txHash, network) {
	var provierNetwork = 'homestead'
	if (network) {
		providerNetwork = network
	}
	const provider = ethers.getDefaultProvider(network)
	provider.getTransaction(txHash).then((tx) => {
		console.log(tx)
		$('#sender-address').val(tx.from)
		$('#receiver-address').val(window.address)
		$('#message').val(ethers.utils.toUtf8String(tx.data))
		$('#ether').val(ethers.utils.formatEther(tx.value))
		$('#loading').hide()
		$('#main').show()
	})
}

function onClickSend() {
	window.open(`./?a=${window.address}`, '_blank')
}

$(()=> {
	console.log("on loaded")

	const address = getUrlParam('a')
	if (address) {
		window.address = address
		$('#button-send').text(`Send congrats to ${address} as well?`)
	}

	const network = getUrlParam('n')
	const txHash = getUrlParam('t')
	if (address && txHash) {
		loadTx(address, txHash, network)
	}

})